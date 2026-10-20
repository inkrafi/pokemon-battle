require "test_helper"

class GameTest < ActiveSupport::TestCase
  setup do
    @alice = Player.create!(name: 'Alice')
    @bob = Player.create!(name: 'Bob')
    @deck_a = build_legal_deck(player: @alice, name: 'Alice deck')
    @deck_b = build_legal_deck(player: @bob, name: 'Bob deck')
  end

  def start_game_record(**options)
    Game.start!(decks: [@deck_a, @deck_b], players: [@alice, @bob], first_player: 0, shuffle: false, **options)
  end

  test "a game starts from two legal decks" do
    game = start_game_record

    assert game.persisted?
    assert_equal 'setup', game.status
    assert_equal [@alice, @bob], [game.player0, game.player1]
    assert_equal 60, game.engine.card_total(0)
    assert_equal 60, game.engine.card_total(1)
  end

  test "a deck that isn't legal can't be used" do
    @deck_b.deck_cards.first.destroy

    error = assert_raises(ArgumentError) { start_game_record }

    assert_match(/Bob deck isn't a legal deck/, error.message)
    assert_no_difference 'Game.count' do
      assert_raises(ArgumentError) { start_game_record }
    end
  end

  test "a move is played and saved" do
    game = start_game_record
    engine = game.engine
    active = engine.player(0)['hand'].find { |uid| engine.card(uid).basic_pokemon? }

    game.perform!(0, 'type' => 'setup', 'active' => active, 'bench' => [])

    reloaded = Game.find(game.id)
    assert_equal [active], reloaded.engine.active(0)['stack']
    assert_equal 'setup', reloaded.status
  end

  test "the game moves on to play and the status follows" do
    game = start_game_record
    2.times do |seat|
      engine = game.engine
      active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
      game.perform!(seat, 'type' => 'setup', 'active' => active, 'bench' => [])
    end

    assert_equal 'play', game.reload.status
    assert_equal 0, game.engine.current
  end

  test "an illegal move is refused and nothing is saved" do
    game = start_game_record
    saved = game.reload.state.to_json

    assert_raises(Tcg::IllegalAction) { game.perform!(0, 'type' => 'end_turn') }

    assert_equal saved, game.reload.state.to_json
  end

  test "a finished game keeps its winner" do
    game = start_game_record

    game.perform!(1, 'type' => 'concede')

    assert game.reload.finished?
    assert_equal 0, game.winner_seat
  end

  test "two moves at the same moment are played one after the other" do
    game = start_game_record
    engine = game.engine
    active = engine.player(0)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    first = Game.find(game.id)
    second = Game.find(game.id) # loaded before the first move was saved

    first.perform!(0, 'type' => 'setup', 'active' => active, 'bench' => [])

    assert_raises(Tcg::IllegalAction) { second.perform!(0, 'type' => 'setup', 'active' => active, 'bench' => []) }
  end

  test "seats_of says where a guest sits, both seats for hotseat" do
    game = start_game_record

    assert_equal [0], game.seats_of(@alice)
    assert_equal [1], game.seats_of(@bob)
    assert_empty game.seats_of(Player.create!)
    assert_empty game.seats_of(nil)

    hotseat = Game.start!(decks: [@deck_a, @deck_a], players: [@alice, @alice])
    assert_equal [0, 1], hotseat.seats_of(@alice)
  end

  test "the engine of a game works on a copy" do
    game = start_game_record
    game.engine.state['phase'] = 'finished'

    assert_equal 'setup', game.engine.phase
  end

  test "a game can be played from the start with the saved decks" do
    game = start_game_record(rng: Random.new(3))
    engine = game.engine
    bot = Tcg::RandomBot.new(rng: Random.new(3))

    bot.play_out(engine)
    game.update!(state: engine.state, status: engine.phase, winner_seat: engine.winner)

    assert game.reload.finished?
    assert_includes [0, 1], game.winner_seat
  end
end
