require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @water = build_legal_deck(name: 'Water starter', sample: true)
    @grass = build_legal_deck(name: 'Grass starter', sample: true)
  end

  def start_game(mode: 'bot', deck0: @water, deck1: @grass)
    post games_url, params: { mode: mode, deck0: deck0.id, deck1: deck1.id }
    Game.order(:id).last
  end

  # A game where it is known who goes first (a coin flip decides it through the page).
  def start_game_with_first_player(first_player, mode: 'bot')
    get games_url # makes this browser a guest
    guest = Player.order(:id).last
    players = mode == 'bot' ? [guest, nil] : [guest, guest]
    Game.start!(decks: [@water, @grass], players: players, mode: mode, first_player: first_player)
  end

  # What the page would post for an action the engine offers.
  def play(game, action)
    post actions_game_url(game), params: action.merge('version' => game.reload.version)
  end

  # The human seat of a game against the computer places the first Basic in hand.
  def place_first_basic(game, seat = 0)
    engine = game.reload.engine
    active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    play(game, 'type' => 'setup', 'active' => active)
  end

  # ---------------------------------------------------------------- starting

  test "the list of games is empty at first" do
    get games_url

    assert_response :success
    assert_select '.empty-state', /No games yet/
  end

  test "the new game page offers modes and decks" do
    get new_game_url

    assert_response :success
    assert_select 'input[name=mode]', 2
    assert_select 'select#deck0 option', 2
    assert_select 'select#deck0 optgroup[label=?]', 'Sample decks'
  end

  test "without any deck there is nothing to play with" do
    DeckCard.delete_all
    Deck.delete_all

    get new_game_url

    assert_select '.empty-state', /No decks to play with/
  end

  test "a guest's own legal decks are offered next to the samples" do
    post decks_url, params: { deck: { name: 'Mine' } }
    deck = Deck.find_by!(name: 'Mine')
    build_legal_deck(player: deck.player, name: 'Legal one')

    get new_game_url

    assert_select 'select#deck0 optgroup[label=?]', 'Your decks'
    assert_select 'select#deck0 option', text: 'Legal one'
    assert_select 'select#deck0 option', text: 'Mine', count: 0 # not a legal deck yet
  end

  test "starting a game against the computer" do
    assert_difference 'Game.count', 1 do
      post games_url, params: { mode: 'bot', deck0: @water.id, deck1: @grass.id }
    end

    game = Game.last
    assert_redirected_to game_url(game)
    assert game.bot?
    assert_equal Player.last, game.player0
    assert_nil game.player1
  end

  test "starting a game on one screen gives the same guest both seats" do
    game = start_game(mode: 'hotseat')

    assert_equal 'hotseat', game.mode
    assert_equal game.player0, game.player1
    assert_equal [0, 1], game.seats_of(game.player0)
  end

  test "a game needs a deck for each side" do
    assert_no_difference 'Game.count' do
      post games_url, params: { mode: 'bot', deck0: @water.id }
    end

    assert_response :unprocessable_entity
    assert_select '.flash--danger', /Choose a legal deck/
  end

  test "somebody else's deck can't be played" do
    stranger = build_legal_deck(player: Player.create!, name: 'Not yours')

    assert_no_difference 'Game.count' do
      post games_url, params: { mode: 'bot', deck0: stranger.id, deck1: @grass.id }
    end

    assert_response :unprocessable_entity
  end

  test "a deck that isn't legal can't be played" do
    post decks_url, params: { deck: { name: 'Half' } }
    half = Deck.find_by!(name: 'Half')
    half.add_card(cards(:sprigling))

    assert_no_difference 'Game.count' do
      post games_url, params: { mode: 'bot', deck0: half.id, deck1: @grass.id }
    end
  end

  test "somebody else's game can't be opened" do
    start_game
    stranger = Game.create!(state: { 'phase' => 'setup' }, player0: Player.create!)

    assert_raises(ActiveRecord::RecordNotFound) { get game_url(stranger) }
    assert_raises(ActiveRecord::RecordNotFound) { post actions_game_url(stranger) }
  end

  test "the list shows the games of the guest" do
    game = start_game

    get games_url

    assert_select '.deck-row h2', "Game ##{game.id}"
    assert_select '.status-chip--live', 'In progress'
  end

  # ---------------------------------------------------------------- against the computer

  test "the first thing in a game is placing the Pokémon" do
    game = start_game

    get game_url(game)

    assert_response :success
    basics = game.engine.player(0)['hand'].count { |uid| game.engine.card(uid).basic_pokemon? }
    assert_select 'h1', /Player 1: place your Pokémon/
    assert_select '.setup-choice', basics
    assert_select 'input[name=active]', basics
  end

  test "placing the Pokémon starts the game and shows the table" do
    game = start_game
    place_first_basic(game)
    follow_redirect!

    assert_response :success
    assert_select '.mat', 2
    assert_select '.hand__cards .hand-card'
    assert_select '.controls', /Your move|Waiting/
  end

  test "the computer's hand is never shown, only its size" do
    game = start_game
    place_first_basic(game)

    get game_url(game)

    assert_select '.mat--theirs .hand-card', 0
    assert_select '.mat--theirs .mat__counts', /Hand/
    assert_select '.hand-card:not(.hand-card--deck)', game.reload.engine.player(0)['hand'].size
  end

  test "a turn starts with drawing a card, which is then marked in the hand" do
    game = start_game_with_first_player(0)
    place_first_basic(game)
    hand = game.reload.engine.player(0)['hand'].size

    get game_url(game)
    assert_select '.hand-card--deck .deck-pile'
    assert_select '.controls', /Draw a card from your deck first/
    assert_select '.hand-card.is-new', 0

    play(game, 'type' => 'draw')
    get game_url(game)

    assert_nil flash[:danger]
    assert_equal hand + 1, game.reload.engine.player(0)['hand'].size
    assert_select '.hand-card--deck', 0
    assert_select '.hand-card.is-new[data-just-drawn=?]', "game-#{game.id}-turn-1", 1
  end

  test "moves the rules don't allow are refused with the reason" do
    game = start_game_with_first_player(0)
    place_first_basic(game)
    play(game, 'type' => 'draw')

    play(game, 'type' => 'attack', 'index' => 0)

    assert_redirected_to game_url(game)
    assert_match(/can't attack on the first turn/, flash[:danger])
  end

  test "a move that isn't a move is refused too" do
    game = start_game_with_first_player(0)
    place_first_basic(game)
    play(game, 'type' => 'draw')

    play(game, 'type' => 'dance')
    assert_match(/Unknown action/, flash[:danger])

    play(game, 'type' => 'bench', 'card' => '99999')
    assert_match(/not in your hand/, flash[:danger])
  end

  test "a move sent in the background is answered with a Turbolinks visit of the board" do
    game = start_game_with_first_player(0)
    place_first_basic(game)

    post actions_game_url(game), params: { type: 'draw', version: game.reload.version }, xhr: true

    assert_match(/Turbolinks\.visit\("#{Regexp.escape(game_url(game))}", \{"action":"replace"\}\)/, response.body)
    assert_nil game.reload.engine.pending
  end

  test "the buttons of the board send their moves in the background" do
    game = start_game_with_first_player(0)
    place_first_basic(game)

    get game_url(game)

    assert_select 'form[data-remote=true] button.deck-pile'
    assert_select '.sound-controls [data-sound-toggle=music]'
    assert_select '[data-fx-deck="0"]'
  end

  test "a page that is out of date can't make a move" do
    game = start_game
    place_first_basic(game)
    stale = game.reload.version
    travel 1.second do
      play(game, 'type' => 'draw')
    end

    post actions_game_url(game), params: { type: 'end_turn', version: stale }

    assert_match(/board changed/, flash[:danger])
  end

  test "a game against the computer can be played through the page to the end" do
    game = start_game
    bot = Tcg::RandomBot.new(rng: Random.new(21))
    renders = 0

    800.times do |step|
      game.reload
      if step % 3 == 0 || game.finished?
        get game_url(game)
        assert_response :success
        renders += 1
      end
      break if game.finished?

      action = bot.choose(game.engine, 0)
      play(game, action)
      assert_nil flash[:danger], "#{action.inspect} was refused: #{flash[:danger]}"
    end

    assert game.reload.finished?
    get game_url(game)
    assert_select '.result h1', /wins/
    assert_select '.hand', 0
    assert_select '.mat', 2
    assert_operator renders, :>=, 2
  end

  test "conceding ends the game and names the winner" do
    game = start_game
    place_first_basic(game)

    play(game, 'type' => 'concede')
    get game_url(game)

    assert game.reload.finished?
    assert_equal 1, game.winner_seat
    assert_select '.result h1', 'Player 2 wins'
    assert_select '.result p', /conceded/
  end

  test "a game that is over takes no more moves" do
    game = start_game
    place_first_basic(game)
    play(game, 'type' => 'concede')

    play(game, 'type' => 'end_turn')

    assert_match(/game is over/, flash[:danger])
  end

  # ---------------------------------------------------------------- two players, one screen

  test "on one screen nobody sees a hand before saying who they are" do
    game = start_game(mode: 'hotseat')

    get game_url(game)

    assert_select '.handoff h1', /Pass the device to Player 1/
    assert_select '.hand-card', 0
    assert_select 'input[name=active]', 0
  end

  test "saying who you are shows that player's side" do
    game = start_game(mode: 'hotseat')

    post reveal_game_url(game)
    follow_redirect!

    assert_select 'h1', /Player 1: place your Pokémon/
  end

  test "after placing Pokémon the device is handed over, then the other player places theirs" do
    game = start_game(mode: 'hotseat')
    post reveal_game_url(game)
    place_first_basic(game, 0)
    follow_redirect!

    assert_select '.handoff h1', /Pass the device to Player 2/
    assert_select '.setup-choice', 0

    post reveal_game_url(game)
    follow_redirect!
    assert_select 'h1', /Player 2: place your Pokémon/
  end

  test "a move can't be made before saying who you are" do
    game = start_game(mode: 'hotseat')

    play(game, 'type' => 'concede')

    assert_match(/Show your side/, flash[:danger])
    assert_not game.reload.finished?
  end

  test "when the turn changes the screen goes back to the hand-over" do
    game = start_game(mode: 'hotseat')
    2.times do |seat|
      post reveal_game_url(game)
      place_first_basic(game, seat)
    end

    first = game.reload.engine.seat_to_act
    post reveal_game_url(game)
    get game_url(game)
    assert_select '.hand__cards'
    assert_select '.controls', /Your move/

    play(game, 'type' => 'draw')
    play(game, 'type' => 'end_turn')
    get game_url(game)

    assert_select '.handoff h1', /Pass the device to Player #{2 - first}/
    assert_select '.hand__cards', 0
  end

  test "revealing a side only works for the player who has to act" do
    game = start_game(mode: 'hotseat')
    post reveal_game_url(game)
    place_first_basic(game, 0)

    post reveal_game_url(game)
    follow_redirect!

    assert_select 'h1', /Player 2: place your Pokémon/ # not Player 1, who has already placed
  end

  test "two players can play a whole game on one screen" do
    game = start_game(mode: 'hotseat')
    bot = Tcg::RandomBot.new(rng: Random.new(33))
    handoffs = 0

    last_seat = nil

    4000.times do
      game.reload
      break if game.finished?

      seat = game.engine.seat_to_act
      if seat != last_seat # the device changes hands
        get game_url(game)
        if css_select('.handoff').any?
          handoffs += 1
          post reveal_game_url(game)
        end
        last_seat = seat
      end

      play(game, bot.choose(game.engine, seat))
      assert_nil flash[:danger], flash[:danger]
    end

    assert game.reload.finished?
    assert_operator handoffs, :>, 5
  end
end
