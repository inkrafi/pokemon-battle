require "test_helper"

# Two guests, each with their own browser, playing against each other.
class GamesOnlineTest < ActionDispatch::IntegrationTest
  setup do
    @water = build_legal_deck(name: 'Water starter', sample: true)
    @grass = build_legal_deck(name: 'Grass starter', sample: true)
    @host = open_session
    @friend = open_session
  end

  # The host opens a game; returns it.
  def open_game
    @host.post online_games_url, params: { deck0: @water.id }
    Game.order(:id).last
  end

  # The friend joins through the invite link; returns the game.
  def join(game)
    @friend.post join_game_url(game.invite_token), params: { deck: @grass.id }
    game.reload
  end

  def started_game
    join(open_game)
  end

  def play(session, game, action)
    session.post actions_game_url(game), params: action.merge('version' => game.reload.version)
  end

  def place(session, game, seat)
    engine = game.reload.engine
    active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    play(session, game, 'type' => 'setup', 'active' => active)
  end

  # ---------------------------------------------------------------- opening and joining

  test "the new game page offers an online game next to the local ones" do
    @host.get new_game_url

    @host.assert_select '.online-panel form[action=?]', online_games_path
    @host.assert_select '.online-panel select#online_deck option', 2
  end

  test "the host gets an invite link and waits" do
    game = open_game

    assert_equal 'waiting', game.status
    assert_equal 'online', game.mode
    @host.assert_redirected_to game_url(game)
    @host.get game_url(game)
    @host.assert_select 'h1', 'Waiting for your opponent'
    @host.assert_select "input#invite-link[value=?]", join_game_url(game.invite_token)
    @host.assert_select "[data-live-game='#{game.id}']"
  end

  test "somebody else's deck can't open a game" do
    stranger = build_legal_deck(player: Player.create!)

    assert_no_difference 'Game.count' do
      @host.post online_games_url, params: { deck0: stranger.id }
    end
    @host.assert_redirected_to new_game_url
  end

  test "a waiting game is listed with its invite link" do
    open_game

    @host.get games_url

    @host.assert_select '.status-chip', 'Waiting for a friend'
    @host.assert_select '.deck-row p', /Online, against a friend/
  end

  test "the invite link asks the friend for a deck" do
    game = open_game

    @friend.get join_game_url(game.invite_token)

    @friend.assert_response :success
    @friend.assert_select 'h1', /invited/
    @friend.assert_select 'select#deck option', 2
  end

  test "a friend joins and both are in the game" do
    game = started_game

    @friend.assert_redirected_to game_url(game)
    assert_equal 'setup', game.status
    assert_equal [0], game.seats_of(game.player0)
    assert_equal [1], game.seats_of(game.player1)
    assert_not_equal game.player0, game.player1
  end

  test "the host opening their own invite goes to the game instead" do
    game = open_game

    @host.get join_game_url(game.invite_token)

    @host.assert_redirected_to game_url(game)
  end

  test "a third person can't join a game that is full" do
    game = started_game
    third = open_session

    third.get join_game_url(game.invite_token)

    third.assert_redirected_to games_url
    third.follow_redirect!
    third.assert_select '.flash--danger', /already has two players/
  end

  test "a friend who is already in the game goes back to it" do
    game = started_game

    @friend.get join_game_url(game.invite_token)

    @friend.assert_redirected_to game_url(game)
  end

  test "an invite link that doesn't exist is a 404" do
    assert_raises(ActiveRecord::RecordNotFound) { @friend.get join_game_url('nonsense') }
  end

  test "joining with a deck that isn't allowed is refused" do
    game = open_game
    stranger = build_legal_deck(player: Player.create!)

    @friend.post join_game_url(game.invite_token), params: { deck: stranger.id }

    @friend.assert_redirected_to join_game_url(game.invite_token)
    assert game.reload.waiting?
  end

  test "nobody can make a move in a game that is still waiting" do
    game = open_game

    @host.post actions_game_url(game), params: { type: 'end_turn', version: game.version }

    @host.assert_redirected_to game_url(game)
    @host.follow_redirect!
    @host.assert_select '.flash--danger', /Wait for your opponent/
  end

  # ---------------------------------------------------------------- playing

  test "each player is asked to place their Pokémon, and then waits for the other" do
    game = started_game

    @host.get game_url(game)
    @host.assert_select 'h1', /Player 1: place your Pokémon/
    @friend.get game_url(game)
    @friend.assert_select 'h1', /Player 2: place your Pokémon/

    place(@friend, game, 1)
    @friend.get game_url(game)
    @friend.assert_select 'h1', 'Waiting for your opponent'
    @friend.assert_select "[data-live-game='#{game.id}']"

    @host.get game_url(game)
    @host.assert_select 'h1', /place your Pokémon/ # still theirs to do
  end

  test "placing Pokémon works from a page drawn before the other player placed theirs" do
    game = started_game
    page_version = game.version
    place(@friend, game, 1) # changes the board

    engine = game.reload.engine
    active = engine.player(0)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    @host.post actions_game_url(game), params: { type: 'setup', active: active, version: page_version }

    assert_nil @host.flash[:danger]
    assert_equal 'play', game.reload.status
  end

  test "once both have placed, the game is on and each side sees only its own hand" do
    game = started_game
    place(@host, game, 0)
    place(@friend, game, 1)

    sizes = game.reload.engine
    @host.get game_url(game)
    @host.assert_select '.mat', 2
    @host.assert_select '.hand-card', sizes.player(0)['hand'].size
    @host.assert_select '.mat--theirs .hand-card', 0
    @friend.get game_url(game)
    @friend.assert_select '.hand-card', sizes.player(1)['hand'].size
    @friend.assert_select "[data-live-game='#{game.id}']"
  end

  test "a player can't move for the other, or when it isn't their turn" do
    game = started_game
    place(@host, game, 0)
    place(@friend, game, 1)
    engine = game.reload.engine
    waiting = engine.seat_to_act == 0 ? @friend : @host

    play(waiting, game, 'type' => 'end_turn')

    assert_match(/not your turn/, waiting.flash[:danger])
    assert_equal engine.current, game.reload.engine.current
  end

  test "the page of the player who waits can't act on an out-of-date board" do
    game = started_game
    place(@host, game, 0)
    place(@friend, game, 1)
    mover = game.reload.engine.seat_to_act == 0 ? @host : @friend
    stale = game.version

    travel 1.second do
      play(mover, game, 'type' => 'end_turn')
    end
    mover.post actions_game_url(game), params: { type: 'end_turn', version: stale }

    assert_match(/board changed/, mover.flash[:danger])
  end

  test "conceding gives the win to the other player and both see the result" do
    game = started_game
    place(@host, game, 0)
    place(@friend, game, 1)

    play(@friend, game, 'type' => 'concede')

    assert game.reload.finished?
    assert_equal 0, game.winner_seat
    [@host, @friend].each do |session|
      session.get game_url(game)
      session.assert_select '.result h1', 'Player 1 wins'
      session.assert_select '[data-live-game]', 0
    end
  end

  test "a whole game can be played between two browsers" do
    game = started_game
    bot = Tcg::RandomBot.new(rng: Random.new(5))
    sessions = [@host, @friend]

    3000.times do |step|
      game.reload
      break if game.finished?

      engine = game.engine
      seats = engine.phase == 'setup' ? [0, 1].reject { |seat| engine.player(seat)['setup_done'] } : [engine.seat_to_act]
      seat = seats.first
      play(sessions[seat], game, bot.choose(engine, seat))
      assert_nil sessions[seat].flash[:danger], "step #{step}, seat #{seat}: #{sessions[seat].flash[:danger]}"
      next unless step % 25 == 0

      sessions[1 - seat].get game_url(game)
      sessions[1 - seat].assert_response :success
    end

    assert game.reload.finished?
    assert_equal [60, 60], [0, 1].map { |s| game.engine.card_total(s) }
  end
end
