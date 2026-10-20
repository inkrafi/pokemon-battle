require "test_helper"

class GameOnlineTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @host = Player.create!(name: 'Host')
    @guest = Player.create!(name: 'Guest')
    @host_deck = build_legal_deck(player: @host)
    @guest_deck = build_legal_deck(player: @guest)
  end

  test "an online game starts out waiting, with an invite token and no board" do
    game = Game.open_online!(deck: @host_deck, host: @host)

    assert game.online?
    assert game.waiting?
    assert game.invite_token.present?
    assert_equal @host, game.player0
    assert_nil game.player1
    assert_raises(RuntimeError) { game.engine }
  end

  test "a deck that isn't legal can't open a game" do
    assert_raises(ArgumentError) { Game.open_online!(deck: @host.decks.create!(name: 'Empty'), host: @host) }
  end

  test "joining seats the second player and starts the game" do
    game = Game.open_online!(deck: @host_deck, host: @host)

    game.join!(player: @guest, deck: @guest_deck, first_player: 1)

    assert_equal 'setup', game.reload.status
    assert_equal @guest, game.player1
    assert_equal [0], game.seats_of(@host)
    assert_equal [1], game.seats_of(@guest)
    assert_equal 1, game.engine.first_player
    assert_nil game.host_deck
    assert_equal [60, 60], [0, 1].map { |seat| game.engine.card_total(seat) }
  end

  test "each side plays its own deck" do
    other = @guest.decks.create!(name: 'Other')
    { sprigling: 4, grass_energy: 56 }.each { |fixture, quantity| other.deck_cards.create!(card: cards(fixture), quantity: quantity) }
    game = Game.open_online!(deck: @host_deck, host: @host)

    game.join!(player: @guest, deck: other)
    engine = game.engine

    assert_equal 60, engine.card_total(0)
    assert_equal 60, engine.card_total(1)
    names = ->(seat) { engine.state['cards'].each_index.select { |uid| engine.player(seat)['deck'].include?(uid) || engine.player(seat)['hand'].include?(uid) }.map { |uid| engine.card(uid).name }.uniq }
    assert_includes names.call(0), 'Emberpup'
    assert_not_includes names.call(1), 'Emberpup'
  end

  test "the host can't take the second seat" do
    game = Game.open_online!(deck: @host_deck, host: @host)

    error = assert_raises(Game::JoinError) { game.join!(player: @host, deck: @host_deck) }

    assert_match(/host of this game/, error.message)
    assert game.reload.waiting?
  end

  test "a game that has two players can't be joined again" do
    game = Game.open_online!(deck: @host_deck, host: @host)
    game.join!(player: @guest, deck: @guest_deck)

    assert_raises(Game::JoinError) { game.join!(player: Player.create!, deck: @guest_deck) }
    assert_equal @guest, game.reload.player1
  end

  test "joining with a deck that isn't legal is refused" do
    game = Game.open_online!(deck: @host_deck, host: @host)
    broken = @guest.decks.create!(name: 'Broken')

    assert_raises(Game::JoinError) { game.join!(player: @guest, deck: broken) }
    assert game.reload.waiting?
  end

  test "both players move on their own seats and nobody plays a computer" do
    game = Game.open_online!(deck: @host_deck, host: @host)
    game.join!(player: @guest, deck: @guest_deck)

    assert_empty game.bot_seats
    assert_equal [], Game.of(Player.create!).to_a
    assert_equal [game], Game.of(@host).to_a
    assert_equal [game], Game.of(@guest).to_a
  end

  test "every change is announced to the people watching the game" do
    game = Game.open_online!(deck: @host_deck, host: @host)

    assert_broadcasts(GameChannel.broadcasting_for(game), 1) do
      game.join!(player: @guest, deck: @guest_deck)
    end

    engine = game.reload.engine
    active = engine.player(0)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    assert_broadcasts(GameChannel.broadcasting_for(game), 1) do
      game.perform!(0, 'type' => 'setup', 'active' => active)
    end
  end

  test "games that are not online announce nothing" do
    assert_no_broadcasts(GameChannel.broadcasting_for(Game.start!(decks: [@host_deck, @host_deck], players: [@host, @host]))) do
      Game.start!(decks: [@host_deck, @host_deck], players: [@host, @host])
    end
  end
end
