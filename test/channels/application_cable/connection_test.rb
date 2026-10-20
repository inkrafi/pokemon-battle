require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "a guest with a cookie is connected as that guest" do
    player = Player.create!
    cookies.signed[:player_token] = player.token

    connect

    assert_equal player, connection.current_player
  end

  test "a browser without a guest is refused" do
    assert_reject_connection { connect }
  end

  test "a cookie that isn't signed is refused" do
    cookies[:player_token] = Player.create!.token

    assert_reject_connection { connect }
  end
end
