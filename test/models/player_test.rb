require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  test "a guest gets a token and a name" do
    player = Player.create!

    assert player.token.present?
    assert_match(/\ATrainer \d{4}\z/, player.name)
  end

  test "tokens are unique" do
    assert_not_equal Player.create!.token, Player.create!.token
  end

  test "the name can be chosen but not too long" do
    assert_equal 'Ash', Player.create!(name: 'Ash').name
    assert_not Player.new(name: 'x' * 25).valid?
  end

  test "deleting a player deletes their decks" do
    player = Player.create!
    player.decks.create!(name: 'Mine')

    assert_difference 'Deck.count', -1 do
      player.destroy
    end
  end
end
