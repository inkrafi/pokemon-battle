require "test_helper"

class Tcg::EngineEffectsTest < ActiveSupport::TestCase
  # Seat 0 attacks seat 1 in turn 2. Both have a Pokémon with 200 HP, seat 0's with the given
  # attack (free to use) and seat 1's with a free 10 damage attack.
  def duel(*effects, damage: 0, attacker_hp: 200, target_hp: 200, bench: false, **options)
    mine = make_card(name: 'Mine', hp: attacker_hp, type: options.fetch(:type, 'Colorless'),
                     attacks: [attack(name: 'Special', cost: [], damage: damage, effects: effects)])
    theirs = make_card(name: 'Theirs', hp: target_hp, attacks: [attack(name: 'Poke', cost: [], damage: 10)])
    engine = start_play(first_player: 1)
    put_in_play(engine, 0, mine, where: :active)
    put_in_play(engine, 1, theirs, where: :active)
    put_in_play(engine, 0, :sprigling) if bench
    put_in_play(engine, 1, :sprigling) if bench
    end_turn(engine)
    engine
  end

  # A coin that gives the listed results in turn, then heads.
  def coins(engine, *results)
    queue = results.dup
    rng = Object.new
    rng.define_singleton_method(:rand) { |*| (queue.empty? ? true : queue.shift) ? 1 : 0 }
    engine.instance_variable_set(:@rng, rng)
  end

  # Seat 0 attacks; when that ends the turn, seat 1 draws the card that starts theirs.
  def attack!(engine)
    engine.perform(0, 'type' => 'attack', 'index' => 0)
    draw_for_turn(engine)
  end

  test "flipping coins for damage counts the heads" do
    engine = duel({ 'op' => 'flip_each', 'coins' => 3, 'per' => 30 })
    coins(engine, true, false, true)

    attack!(engine)

    assert_equal 60, engine.active(1)['damage']
  end

  test "flipping until tails" do
    engine = duel({ 'op' => 'flip_until_tails', 'per' => 20 })
    coins(engine, true, true, true, false)

    attack!(engine)

    assert_equal 60, engine.active(1)['damage']
  end

  test "flipping until tails for more damage adds to the base damage" do
    engine = duel({ 'op' => 'flip_until_tails', 'per' => 20, 'plus' => true }, damage: 30)
    coins(engine, true, false)

    attack!(engine)

    assert_equal 50, engine.active(1)['damage']
  end

  test "a coin for bonus damage" do
    engine = duel({ 'op' => 'flip_bonus', 'bonus' => 40 }, damage: 20)
    coins(engine, true)
    attack!(engine)
    assert_equal 60, engine.active(1)['damage']

    engine = duel({ 'op' => 'flip_bonus', 'bonus' => 40 }, damage: 20)
    coins(engine, false)
    attack!(engine)
    assert_equal 20, engine.active(1)['damage']
  end

  test "both coins must be heads for the bonus" do
    engine = duel({ 'op' => 'flip_both_bonus', 'bonus' => 50 }, damage: 10)
    coins(engine, true, false)

    attack!(engine)

    assert_equal 10, engine.active(1)['damage']
  end

  test "tails can make the whole attack do nothing" do
    engine = duel({ 'op' => 'flip_or_nothing' }, { 'op' => 'inflict', 'condition' => 'poisoned' }, damage: 50)
    coins(engine, false)

    attack!(engine)

    assert_equal 0, engine.active(1)['damage']
    assert_empty engine.active(1)['conditions']
    assert_equal 1, engine.current # the turn still ends
  end

  test "a Special Condition is inflicted on the Defending Pokémon" do
    engine = duel({ 'op' => 'inflict', 'condition' => 'burned' }, { 'op' => 'inflict', 'condition' => 'poisoned' }, damage: 10)
    coins(engine, false) # the Burn doesn't heal in the Checkup

    attack!(engine)

    assert_equal %w[burned poisoned], engine.active(1)['conditions'].sort
    assert_equal 30, engine.active(1)['damage'] # 10 attack, 10 Poison, 10 Burn
  end

  test "a Special Condition that needs heads doesn't land on tails" do
    engine = duel({ 'op' => 'inflict', 'condition' => 'paralyzed', 'if' => 'heads' })
    coins(engine, false)

    attack!(engine)

    assert_empty engine.active(1)['conditions']
  end

  test "bonus damage from the board" do
    engine = duel({ 'op' => 'plus_if_self_damaged', 'bonus' => 30 }, { 'op' => 'plus_if_target_damaged', 'bonus' => 20 }, damage: 10)
    engine.active(0)['damage'] = 10
    engine.active(1)['damage'] = 10

    attack!(engine)

    assert_equal 10 + 60, engine.active(1)['damage']
  end

  test "damage for each Energy" do
    engine = duel({ 'op' => 'plus_per_energy', 'per' => 20, 'type' => 'Fire' }, damage: 10)
    3.times { engine.active(0)['energy'] << give(engine, 0, :fire_energy, zone: 'discard').tap { |u| engine.player(0)['discard'].delete(u) } }
    engine.active(0)['energy'] << give(engine, 0, :grass_energy, zone: 'discard').tap { |u| engine.player(0)['discard'].delete(u) }

    attack!(engine)

    assert_equal 70, engine.active(1)['damage']
  end

  test "damage for each Prize card taken" do
    engine = duel({ 'op' => 'per_prize_taken', 'per' => 30 })
    engine.player(0)['prizes'].pop(2)

    attack!(engine)

    assert_equal 60, engine.active(1)['damage']
  end

  test "damage for each damage counter on the Defender" do
    engine = duel({ 'op' => 'per_target_counter', 'per' => 10 })
    engine.active(1)['damage'] = 50

    attack!(engine)

    assert_equal 100, engine.active(1)['damage']
  end

  test "a Pokémon ex takes bonus damage" do
    engine = duel({ 'op' => 'plus_if_target_ex', 'bonus' => 50 }, damage: 10)
    engine.active(1)['stack'] # not an ex yet
    attack!(engine)
    assert_equal 10, engine.active(1)['damage']
  end

  test "healing and recoil" do
    engine = duel({ 'op' => 'heal_self', 'amount' => 30 }, { 'op' => 'recoil', 'amount' => 10 }, damage: 20)
    engine.active(0)['damage'] = 20

    attack!(engine)

    assert_equal 10, engine.active(0)['damage'] # healed the 20 there was, then 10 recoil
  end

  test "recoil can knock out the attacker and the opponent takes the Prize" do
    engine = duel({ 'op' => 'recoil', 'amount' => 100 }, attacker_hp: 100, bench: true)

    attack!(engine)

    assert_equal 5, engine.player(1)['prizes'].size
    assert_equal 0, engine.pending['seat']
  end

  test "discarding Energy from the attacker" do
    engine = duel({ 'op' => 'discard_self_energy', 'count' => 'all' }, damage: 10)
    2.times { engine.active(0)['energy'] << give(engine, 0, :fire_energy, zone: 'discard').tap { |u| engine.player(0)['discard'].delete(u) } }

    attack!(engine)

    assert_empty engine.active(0)['energy']
  end

  test "drawing cards" do
    engine = duel({ 'op' => 'draw', 'count' => 2 })
    hand = engine.player(0)['hand'].size

    attack!(engine)

    assert_equal hand + 2, engine.player(0)['hand'].size
  end

  test "discarding the top of the opponent's deck" do
    engine = duel({ 'op' => 'mill_opponent', 'count' => 2 })
    deck = engine.player(1)['deck'].size

    attack!(engine)

    assert_equal deck - 2 - 1, engine.player(1)['deck'].size # and their draw for the next turn
  end

  test "less damage from attacks during the next turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'self', 'kind' => 'reduce_incoming', 'amount' => 10, 'turns' => 1 })
    attack!(engine)

    engine.perform(1, 'type' => 'attack', 'index' => 0) # Poke does 10, takes 10 less

    assert_equal 0, engine.active(0)['damage']
  end

  test "the protection ends after the opponent's turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'self', 'kind' => 'reduce_incoming', 'amount' => 10, 'turns' => 1 })
    attack!(engine)
    end_turn(engine)
    end_turn(engine)

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 10, engine.active(0)['damage']
  end

  test "the Defending Pokémon does less damage next turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'defender', 'kind' => 'reduce_outgoing', 'amount' => 10, 'turns' => 1 })
    attack!(engine)

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 0, engine.active(0)['damage']
  end

  test "the Defending Pokémon can't retreat next turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'defender', 'kind' => 'no_retreat', 'turns' => 1 }, bench: true)
    attack!(engine)

    assert_match(/can't retreat right now/, engine.error_for(1, 'type' => 'retreat', 'to' => 0, 'energy' => []))
  end

  test "all damage can be prevented for a turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'self', 'kind' => 'protect_all', 'turns' => 1 })
    attack!(engine)

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 0, engine.active(0)['damage']
  end

  test "a Pokémon that can't use an attack next turn is blocked in its own next turn" do
    engine = duel({ 'op' => 'mark', 'target' => 'self', 'kind' => 'no_attack', 'name' => 'Special', 'turns' => 2 })
    attack!(engine)
    end_turn(engine)

    assert_match(/can't attack right now/, engine.error_for(0, 'type' => 'attack', 'index' => 0))

    end_turn(engine)
    end_turn(engine)
    assert_nil engine.error_for(0, 'type' => 'attack', 'index' => 0)
  end

  test "the Defending Pokémon is Knocked Out at exactly the right number of damage counters" do
    engine = duel({ 'op' => 'knock_out_if_counters', 'counters' => 4 }, target_hp: 100, bench: true)
    engine.active(1)['damage'] = 40

    attack!(engine)

    assert_equal 5, engine.player(0)['prizes'].size
  end

  test "switching out the Defending Pokémon lets its owner choose the new one" do
    engine = duel({ 'op' => 'switch_opponent' }, bench: true)
    attack!(engine)

    assert_equal 'switch', engine.pending['type']
    assert_equal 1, engine.pending['seat']
    assert_equal [{ 'type' => 'switch', 'index' => 0 }, { 'type' => 'concede' }], engine.legal_actions(1)

    engine.perform(1, 'type' => 'switch', 'index' => 0)

    assert_equal 'Sprigling', engine.top_card(engine.active(1)).name
    assert_equal({ 'type' => 'draw', 'seat' => 1 }, engine.pending) # their turn starts with a draw
    assert_equal 1, engine.current
  end

  test "switching your own Pokémon after an attack, which may be declined" do
    engine = duel({ 'op' => 'switch_self', 'optional' => true }, bench: true)
    attack!(engine)

    assert engine.legal_actions(0).include?({ 'type' => 'switch', 'skip' => true })
    engine.perform(0, 'type' => 'switch', 'skip' => true)

    assert_equal 'Mine', engine.top_card(engine.active(0)).name
    assert_equal 1, engine.current
  end

  test "an attack that switches does nothing extra when there is no Bench" do
    engine = duel({ 'op' => 'switch_self' })

    attack!(engine)

    assert_nil engine.pending
    assert_equal 1, engine.current
  end

  test "Conditions are cured when a Pokémon is switched out" do
    engine = duel({ 'op' => 'switch_opponent' }, { 'op' => 'inflict', 'condition' => 'poisoned' }, bench: true)
    attack!(engine)
    old = engine.active(1)
    engine.perform(1, 'type' => 'switch', 'index' => 0)

    assert_empty old['conditions']
  end

  test "Weakness and Resistance can be ignored" do
    fire = make_card(name: 'Fire-type', hp: 200, type: 'Fire', attacks: [attack(name: 'Special', cost: [], damage: 30, effects: [{ 'op' => 'ignore', 'what' => 'matchup' }])])
    engine = start_play(first_player: 1)
    put_in_play(engine, 0, fire, where: :active)
    end_turn(engine)

    attack!(engine)

    assert_equal 30, engine.active(1)['damage'] # Sprigling is weak to Fire
  end

  test "an attack that searches the deck asks for the choice before the turn ends" do
    engine = duel({ 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'energy', 'basic_energy' => true }] }, damage: 10)
    energy = give(engine, 0, :fire_energy, zone: 'deck')

    attack!(engine)

    assert_equal 'search', engine.pending['type']
    assert_equal 0, engine.current
    engine.perform(0, 'type' => 'choose', 'cards' => [energy])

    assert_includes engine.player(0)['hand'], energy
    assert_equal 1, engine.current
    assert_equal 10, engine.active(1)['damage']
  end

  test "an attack that attaches Energy from the deck to the attacker" do
    filter = { 'supertype' => 'energy', 'basic_energy' => true, 'type' => 'Fire' }
    engine = duel({ 'op' => 'search', 'to' => 'self', 'filters' => [filter] })
    energy = give(engine, 0, :fire_energy, zone: 'deck')

    attack!(engine)
    engine.perform(0, 'type' => 'choose', 'cards' => [energy])

    assert_equal [energy], engine.active(0)['energy']
  end

  test "bonus damage for the Prize cards left" do
    engine = duel({ 'op' => 'plus_if_own_prizes', 'prizes' => 6, 'bonus' => 50 }, { 'op' => 'plus_if_opponent_prizes_at_most', 'prizes' => 2, 'bonus' => 40 }, damage: 10)
    engine.player(1)['prizes'].pop(4)

    attack!(engine)

    assert_equal 100, engine.active(1)['damage']
  end
end
