require "test_helper"

class Tcg::EngineCombatTest < ActiveSupport::TestCase
  # Seat 1 goes first and ends their turn, so seat 0 is to move in turn 2: a turn in which
  # attacking is allowed.
  def second_turn(actives:)
    basics = actives.map { |name| cards(name).basic_pokemon? ? name : :sprigling }
    engine = start_play(first_player: 1, actives: basics)
    actives.each_with_index { |name, seat| put_in_play(engine, seat, name, where: :active) unless cards(name).basic_pokemon? }
    engine.perform(1, 'type' => 'end_turn')
    engine
  end

  def energize(engine, seat, fixture, count = 1)
    count.times do
      uid = give(engine, seat, fixture, zone: 'discard')
      engine.player(seat)['discard'].delete(uid)
      engine.active(seat)['energy'] << uid
    end
  end

  # ---------------------------------------------------------------- who may attack

  test "the player who goes first can't attack on the first turn" do
    engine = start_play(first_player: 0)
    energize(engine, 0, :grass_energy)

    assert_match(/goes first can't attack/, engine.error_for(0, 'type' => 'attack', 'index' => 0))
  end

  test "the other player can attack on their first turn" do
    engine = second_turn(actives: %i[sprigling sprigling])
    energize(engine, 0, :grass_energy)

    assert_nil engine.error_for(0, 'type' => 'attack', 'index' => 0)
  end

  test "an attack needs its Energy" do
    engine = second_turn(actives: %i[sprigling sprigling])

    assert_match(/Not enough Energy for Leaf Poke/, engine.error_for(0, 'type' => 'attack', 'index' => 0))
  end

  test "colored Energy has to match the type on the attack" do
    engine = second_turn(actives: %i[sprigling sprigling])
    energize(engine, 0, :fire_energy)

    assert_match(/Not enough Energy/, engine.error_for(0, 'type' => 'attack', 'index' => 0))
  end

  test "Colorless can be paid with any Energy" do
    engine = second_turn(actives: %i[bloomling sprigling]) # Petal Slash costs Grass and Colorless
    energize(engine, 0, :grass_energy)
    assert_match(/Not enough Energy/, engine.error_for(0, 'type' => 'attack', 'index' => 0))

    energize(engine, 0, :fire_energy)
    assert_nil engine.error_for(0, 'type' => 'attack', 'index' => 0)
  end

  test "an attack with an effect can't be used yet" do
    engine = second_turn(actives: %i[shellpal sprigling])
    energize(engine, 0, :water_energy, 2)

    assert_match(/Tidal Crash has an effect/, engine.error_for(0, 'type' => 'attack', 'index' => 1))
    assert_nil engine.error_for(0, 'type' => 'attack', 'index' => 0)
  end

  test "an attack that doesn't exist can't be chosen" do
    engine = second_turn(actives: %i[sprigling sprigling])
    energize(engine, 0, :grass_energy)

    [-1, 5, nil, 'first'].each do |index|
      assert_match(/Choose one of the attacks/, engine.error_for(0, 'type' => 'attack', 'index' => index), index.inspect)
    end
  end

  # ---------------------------------------------------------------- damage

  test "an attack puts damage on the opponent's Active Pokémon and ends the turn" do
    engine = second_turn(actives: %i[sprigling bloomling])
    energize(engine, 0, :grass_energy)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 20, engine.active(1)['damage'] # Leaf Poke does 20
    assert_equal 90, engine.hp_left(engine.active(1)) # Bloomling has 110 HP
    assert_equal 1, engine.current
    assert_equal 3, engine.turn_number
  end

  test "damage builds up over several attacks" do
    engine = second_turn(actives: %i[sprigling bloomling])
    energize(engine, 0, :grass_energy)
    engine.perform(0, 'type' => 'attack', 'index' => 0)
    engine.perform(1, 'type' => 'end_turn')

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 40, engine.active(1)['damage']
  end

  test "Weakness doubles the damage" do
    engine = second_turn(actives: %i[emberpup bloomling]) # Bloomling is weak to Fire
    energize(engine, 0, :fire_energy)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 60, engine.active(1)['damage'] # Spark does 30
  end

  test "Resistance takes 30 off" do
    engine = second_turn(actives: %i[sprigling bloomling]) # Bloomling resists Water
    put_in_play(engine, 0, make_card(name: 'Wavemon', type: 'Water', attacks: [attack(damage: 50, cost: ['Water'])]), where: :active)
    energize(engine, 0, :water_energy)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 20, engine.active(1)['damage']
  end

  test "Resistance can't make damage negative" do
    engine = second_turn(actives: %i[shellpal bloomling])
    energize(engine, 0, :water_energy)

    engine.perform(0, 'type' => 'attack', 'index' => 0) # Splash does 20, minus 30

    assert_equal 0, engine.active(1)['damage']
  end

  test "an attack without damage only ends the turn" do
    engine = second_turn(actives: %i[sprigling sprigling])
    put_in_play(engine, 0, make_card(name: 'Quietmon', attacks: [attack(damage: nil, cost: [])]), where: :active)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 0, engine.active(1)['damage']
    assert_equal 1, engine.current
  end

  # ---------------------------------------------------------------- Knock Out

  def knock_out_setup(defender_card: nil, bench: true)
    engine = second_turn(actives: %i[emberpup sprigling]) # Spark does 60 to a Sprigling
    energize(engine, 0, :fire_energy)
    put_in_play(engine, 1, :sprigling) if bench
    put_in_play(engine, 1, defender_card, where: :active) if defender_card
    engine
  end

  test "a Knocked Out Pokémon goes to the discard pile with its Energy and the attacker takes a Prize card" do
    engine = knock_out_setup
    energize(engine, 1, :grass_energy)
    fallen = engine.active(1)['stack'] + engine.active(1)['energy']
    hand_before = engine.player(0)['hand'].size

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_nil engine.active(1)
    assert_empty fallen - engine.player(1)['discard']
    assert_equal 5, engine.player(0)['prizes'].size
    assert_equal hand_before + 1, engine.player(0)['hand'].size
  end

  test "the player who lost a Pokémon chooses a new Active one before the game goes on" do
    engine = knock_out_setup
    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal({ 'type' => 'promote', 'seat' => 1, 'queue' => [], 'ended' => 0, 'stage' => 'checkup' }, engine.pending)
    assert_match(/opponent is choosing/, engine.error_for(0, 'type' => 'end_turn'))
    assert_match(/Choose your new Active/, engine.error_for(1, 'type' => 'end_turn'))
    assert_equal [{ 'type' => 'promote', 'index' => 0 }, { 'type' => 'concede' }], engine.legal_actions(1)
    assert_match(/Choose a Pokémon from your Bench/, engine.error_for(1, 'type' => 'promote', 'index' => 3))

    hand_before = engine.player(1)['hand'].size
    engine.perform(1, 'type' => 'promote', 'index' => 0)

    assert_equal 'Sprigling', engine.top_card(engine.active(1)).name
    assert_empty engine.bench(1)
    assert_nil engine.pending
    assert_equal 1, engine.current
    assert_equal hand_before + 1, engine.player(1)['hand'].size # their turn began with a draw
  end

  test "knocking out the last Pokémon in play wins the game" do
    engine = knock_out_setup(bench: false)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert engine.finished?
    assert_equal 0, engine.winner
    assert_equal 'no_pokemon', engine.win_reason
  end

  test "taking the last Prize card wins the game" do
    engine = knock_out_setup
    engine.player(0)['prizes'] = [engine.player(0)['prizes'].first]

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert engine.finished?
    assert_equal 0, engine.winner
    assert_equal 'prizes', engine.win_reason
    assert_nil engine.pending
  end

  test "a Pokémon ex gives up two Prize cards and a Mega ex three" do
    {2 => 4, 3 => 3}.each do |prize_value, left|
      big = make_card(name: "Bigmon #{prize_value}", hp: 20, prize_value: prize_value)
      engine = knock_out_setup(defender_card: big)

      engine.perform(0, 'type' => 'attack', 'index' => 0)

      assert_equal left, engine.player(0)['prizes'].size, "prize value #{prize_value}"
    end
  end

  test "only the Prize cards that are left are taken" do
    big = make_card(name: 'Bigmon', hp: 20, prize_value: 3)
    engine = knock_out_setup(defender_card: big)
    engine.player(0)['prizes'] = engine.player(0)['prizes'].first(2)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_empty engine.player(0)['prizes']
    assert_equal 0, engine.winner
  end

  test "the evolved card decides how many Prize cards a Pokémon gives up" do
    engine = knock_out_setup
    top = make_card(name: 'Bloomling ex', hp: 30, prize_value: 2, subtype: 'stage1', evolves_from: 'Sprigling')
    slot = engine.active(1)
    slot['stack'] << give(engine, 1, top, zone: 'discard')
    engine.player(1)['discard'].pop

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 4, engine.player(0)['prizes'].size
  end

  # ---------------------------------------------------------------- the end of the game

  test "nothing can be done once the game is over" do
    engine = knock_out_setup(bench: false)
    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 'The game is over.', engine.error_for(0, 'type' => 'end_turn')
    assert_equal 'The game is over.', engine.error_for(1, 'type' => 'concede')
    assert_empty engine.legal_actions(0)
    assert_raises(Tcg::IllegalAction) { engine.perform(1, 'type' => 'end_turn') }
  end

  test "a player can concede at any time, even out of turn" do
    engine = start_play(first_player: 0)

    engine.perform(1, 'type' => 'concede')

    assert engine.finished?
    assert_equal 0, engine.winner
    assert_equal 'concede', engine.win_reason
  end

  test "no Energy or Pokémon is created or lost during a fight" do
    engine = knock_out_setup
    totals = [0, 1].map { |seat| engine.card_total(seat) }

    engine.perform(0, 'type' => 'attack', 'index' => 0)
    engine.perform(1, 'type' => 'promote', 'index' => 0)

    assert_equal totals, [0, 1].map { |seat| engine.card_total(seat) }
  end
end
