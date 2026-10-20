require "test_helper"

class GameChannelTest < ActionCable::Channel::TestCase
  setup do
    @host = Player.create!
    @guest = Player.create!
    @game = Game.open_online!(deck: build_legal_deck(player: @host), host: @host)
    @game.join!(player: @guest, deck: build_legal_deck(player: @guest))
  end

  test "both players of a game can listen to it" do
    [@host, @guest].each do |player|
      stub_connection current_player: player
      subscribe id: @game.id

      assert subscription.confirmed?
      assert_has_stream_for @game
    end
  end

  test "somebody who isn't in the game is turned away" do
    stub_connection current_player: Player.create!

    subscribe id: @game.id

    assert subscription.rejected?
  end

  test "a game that doesn't exist is turned away too" do
    stub_connection current_player: @host

    subscribe id: 0

    assert subscription.rejected?
  end
end
