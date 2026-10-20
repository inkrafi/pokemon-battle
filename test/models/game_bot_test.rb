require "test_helper"

# Games against the computer: seat 1 is played by Tcg::RandomBot, right after each human move.
class GameBotTest < ActiveSupport::TestCase
  setup do
    @human = Player.create!(name: 'Human')
    @deck = build_legal_deck(player: @human)
  end

  def start_bot_game(first_player: 0)
    Game.start!(decks: [@deck, @deck], players: [@human, nil], mode: 'bot', first_player: first_player, shuffle: false)
  end

  def place_first_basic(game, seat = 0)
    engine = game.engine
    active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    game.perform!(seat, 'type' => 'setup', 'active' => active, 'bench' => [])
  end

  test "a game has a mode, hotseat unless said otherwise" do
    assert_equal 'hotseat', Game.start!(decks: [@deck, @deck], players: [@human, @human]).mode
    assert start_bot_game.bot?
    assert_equal [1], start_bot_game.bot_seats
    assert_empty Game.start!(decks: [@deck, @deck]).bot_seats
    assert_not Game.new(mode: 'telepathy').valid?
  end

  test "the computer places its Pokémon as soon as the human has placed theirs" do
    game = start_bot_game
    place_first_basic(game)

    engine = game.reload.engine
    assert_equal 'play', engine.phase
    assert engine.player(1)['setup_done']
    assert_equal 0, engine.seat_to_act # the human goes first
  end

  test "when the computer goes first it has already played by the time the human can move" do
    game = start_bot_game(first_player: 1)
    place_first_basic(game)

    engine = game.reload.engine
    assert_equal 0, engine.seat_to_act
    assert_equal 2, engine.turn_number # its turn, then the start of the human's
    assert_match(/Player 2/, engine.log.map { |entry| entry['text'] }.join("\n"))
  end

  test "the computer answers after each human move" do
    game = start_bot_game
    place_first_basic(game)

    game.perform!(0, 'type' => 'end_turn')

    engine = game.reload.engine
    assert_equal 0, engine.seat_to_act
    assert_operator engine.turn_number, :>=, 3
  end

  test "a game against the computer can be played to the end" do
    game = start_bot_game
    bot = Tcg::RandomBot.new(rng: Random.new(9))

    1000.times do
      break if game.reload.finished?

      engine = game.engine
      game.perform!(0, bot.choose(engine, 0))
    end

    assert game.reload.finished?
    assert_includes [0, 1], game.winner_seat
  end

  test "the version changes with every move" do
    game = start_bot_game
    before = game.version

    travel 1.second do
      place_first_basic(game)
    end

    assert_not_equal before, game.reload.version
  end

  test "games are found by the people in them" do
    game = start_bot_game
    other = Player.create!

    assert_includes Game.of(@human), game
    assert_not_includes Game.of(other), game
  end
end
