require "test_helper"

# Random games: whatever the bot does, the rules have to hold.
class Tcg::EngineSimulationTest < ActiveSupport::TestCase
  MAX_ACTIONS = 5000

  # Plays a whole game, checking the invariants after every move.
  def play_checking(engine, bot)
    actions = 0
    until engine.finished?
      seat = engine.seat_to_act
      action = bot.choose(engine, seat)
      assert action, "seat #{seat} had no move in phase #{engine.phase}"
      engine.perform(seat, action)

      assert_equal [60, 60], [0, 1].map { |s| engine.card_total(s) }, "a card appeared or vanished after #{action.inspect}"
      assert_operator engine.bench(0).size, :<=, Tcg::Engine::BENCH_SIZE
      assert_operator engine.bench(1).size, :<=, Tcg::Engine::BENCH_SIZE
      if engine.phase == 'play' && engine.pending.nil?
        assert engine.active(0) && engine.active(1), 'a player has no Active Pokémon'
      end

      actions += 1
      flunk "the game didn't end within #{MAX_ACTIONS} actions" if actions > MAX_ACTIONS
    end
    engine
  end

  test "random games always end with a winner and a reason, and never lose a card" do
    reasons = Hash.new(0)

    30.times do |seed|
      engine = Tcg::Engine.start(decks: [mixed_deck_ids, mixed_deck_ids], rng: Random.new(seed))
      play_checking(engine, Tcg::RandomBot.new(rng: Random.new(seed)))

      assert_includes [0, 1], engine.winner, "seed #{seed}"
      assert_includes %w[prizes no_pokemon deck_out], engine.win_reason, "seed #{seed}"
      reasons[engine.win_reason] += 1
    end

    assert_operator reasons.values.sum, :==, 30
  end

  test "a game is repeatable: the same seeds give the same game" do
    play = lambda do
      engine = Tcg::Engine.start(decks: [mixed_deck_ids, mixed_deck_ids], rng: Random.new(7))
      Tcg::RandomBot.new(rng: Random.new(7)).play_out(engine)
      [engine.winner, engine.win_reason, engine.turn_number, engine.log.size]
    end

    assert_equal play.call, play.call
  end

  test "a finished game can be reloaded from its saved state" do
    engine = Tcg::Engine.start(decks: [mixed_deck_ids, mixed_deck_ids], rng: Random.new(4))
    Tcg::RandomBot.new(rng: Random.new(4)).play_out(engine)

    reloaded = Tcg::Engine.new(JSON.parse(engine.state.to_json))

    assert reloaded.finished?
    assert_equal [engine.winner, engine.win_reason], [reloaded.winner, reloaded.win_reason]
  end

  test "the game ends however it is played: by the bot picking only the first move" do
    engine = Tcg::Engine.start(decks: [mixed_deck_ids, mixed_deck_ids], rng: Random.new(2))

    2000.times do
      break if engine.finished?

      seat = engine.seat_to_act
      actions = engine.legal_actions(seat).reject { |action| action['type'] == 'concede' }
      engine.perform(seat, actions.first)
    end

    assert engine.finished?
  end

  test "the log never grows without bound" do
    engine = Tcg::Engine.start(decks: [mixed_deck_ids, mixed_deck_ids], rng: Random.new(5))
    Tcg::RandomBot.new(rng: Random.new(5)).play_out(engine)

    assert_operator engine.log.size, :<=, Tcg::Engine::LOG_LIMIT
  end
end
