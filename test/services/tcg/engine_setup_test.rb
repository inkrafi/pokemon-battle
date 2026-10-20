require "test_helper"

class Tcg::EngineSetupTest < ActiveSupport::TestCase
  test "each player draws seven cards and keeps the rest in the deck" do
    engine = start_game

    2.times do |seat|
      assert_equal 7, engine.player(seat)['hand'].size
      assert_equal 53, engine.player(seat)['deck'].size
      assert_equal 60, engine.card_total(seat)
    end
    assert_equal 'setup', engine.phase
  end

  test "a coin flip decides who goes first unless it is given" do
    firsts = (1..30).map { |seed| start_game(first_player: nil, seed: seed).first_player }

    assert_equal [0, 1], firsts.uniq.sort
    assert_equal 1, start_game(first_player: 1).first_player
  end

  test "a hand without a Basic Pokémon is shuffled back, and the opponent draws an extra card for each time" do
    energy_first = [cards(:fire_energy).id] * 22 + [cards(:sprigling).id] * 4 + [cards(:bloomling).id] * 4 +
                   [cards(:emberpup).id] * 4 + [cards(:shellpal).id] * 4 + [cards(:grass_energy).id] * 22

    engine = start_game(decks: [energy_first, mixed_deck_ids])

    assert_equal 3, engine.player(0)['mulligans']
    assert_equal 7, engine.player(0)['hand'].size
    assert engine.player(0)['hand'].any? { |uid| engine.card(uid).basic_pokemon? }
    assert_equal 10, engine.player(1)['hand'].size # 7 plus 3 extra
    assert_equal 60, engine.card_total(0)
    assert_equal 60, engine.card_total(1)
  end

  test "a deck without any Basic Pokémon can't start a game" do
    energy_only = [cards(:fire_energy).id] * 60

    assert_raises(ArgumentError) { start_game(decks: [energy_only, mixed_deck_ids]) }
  end

  test "both players must place an Active Pokémon before anything else happens" do
    engine = start_game

    assert_equal 'Place your Pokémon first.', engine.error_for(0, 'type' => 'end_turn')
    assert_equal ['setup', 'concede'].sort, engine.legal_actions(0).map { |action| action['type'] }.uniq.sort
  end

  test "a player puts one Basic Pokémon Active and up to five on the Bench" do
    engine = start_game
    active = uid_of(engine, 0, :sprigling)

    engine.perform(0, 'type' => 'setup', 'active' => active, 'bench' => [])

    assert_equal [active], engine.active(0)['stack']
    assert_empty engine.bench(0)
    assert_equal 6, engine.player(0)['hand'].size
  end

  test "bench Pokémon are placed in the same step" do
    engine = start_game
    hand = engine.player(0)['hand'].select { |uid| engine.card(uid).basic_pokemon? }

    engine.perform(0, 'type' => 'setup', 'active' => hand[0], 'bench' => hand[1..3])

    assert_equal 3, engine.bench(0).size
    assert_equal 3, engine.player(0)['hand'].size
  end

  test "the Bench holds at most five" do
    engine = start_game
    basics = 7.times.map { give(engine, 0, :sprigling) } # one Active, six for the Bench

    error = engine.error_for(0, 'type' => 'setup', 'active' => basics[0], 'bench' => basics[1..])

    assert_match(/Bench holds at most 5/, error)
  end

  test "only Basic Pokémon from the hand can be placed" do
    engine = start_game
    evolution = uid_of(engine, 0, :bloomling)
    energy = give(engine, 0, :fire_energy)
    sprig = uid_of(engine, 0, :sprigling)

    assert_match(/Only Basic Pokémon/, engine.error_for(0, 'type' => 'setup', 'active' => evolution))
    assert_match(/Only Basic Pokémon/, engine.error_for(0, 'type' => 'setup', 'active' => energy))
    assert_match(/not all in your hand/, engine.error_for(0, 'type' => 'setup', 'active' => 99_999))
    assert_match(/not all in your hand/, engine.error_for(0, 'type' => 'setup', 'active' => sprig, 'bench' => [sprig]))
    assert_match(/Choose a Basic Pokémon/, engine.error_for(0, 'type' => 'setup'))
  end

  test "setup can only be done once" do
    engine = start_game
    engine.perform(0, 'type' => 'setup', 'active' => uid_of(engine, 0, :sprigling), 'bench' => [])

    assert_match(/already placed/, engine.error_for(0, 'type' => 'setup', 'active' => uid_of(engine, 0, :sprigling)))
  end

  test "the game begins when both have placed their Pokémon" do
    engine = start_play(first_player: 1)

    assert_equal 'play', engine.phase
    assert_equal 1, engine.current
    assert_equal 1, engine.turn_number
    2.times { |seat| assert_equal 6, engine.player(seat)['prizes'].size }
    assert_equal 60, engine.card_total(0)
  end

  test "the player who goes first draws at the start of the turn" do
    engine = start_play(first_player: 0)

    assert_equal 7, engine.player(0)['hand'].size # 7 - Active + 1 drawn
    assert_equal 6, engine.player(1)['hand'].size
  end

  test "nobody can act in setup before it is done, except to concede" do
    engine = start_game

    assert_equal [{ 'type' => 'concede' }], engine.legal_actions(0).select { |action| action['type'] == 'concede' }
    engine.perform(1, 'type' => 'concede')

    assert engine.finished?
    assert_equal 0, engine.winner
    assert_equal 'concede', engine.win_reason
  end
end
