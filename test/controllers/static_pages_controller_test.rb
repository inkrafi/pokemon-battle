require "test_helper"

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  test "home shows a hand of cards when the library is big enough" do
    get root_url

    assert_response :success
    assert_select '.card-fan .tcg-card', 3
    assert_select 'a', 'Play a game'
    assert_select 'a', 'Browse the cards'
  end

  test "home says how to load cards when there are none" do
    DeckCard.delete_all
    Card.delete_all

    get root_url

    assert_response :success
    assert_select '.empty-state', /No cards yet/
  end

  test "home only deals cards that can be played" do
    Card.where.not(id: [cards(:sprigling).id, cards(:emberpup).id, cards(:shellpal).id]).update_all(playable: false)

    get root_url

    assert_select '.card-fan .tcg-card', 3
  end

  test "the guide covers the rules" do
    get about_url

    assert_response :success
    %w[Setting\ up A\ turn Special\ Conditions Deck\ rules].each do |heading|
      assert_select 'h2', heading
    end
  end

  test "the guide links to the official rules" do
    get about_url

    assert_select 'a[href=?]', 'https://tcg.pokemon.com/en-us/learn/'
  end

  test "only the cards on the home page follow the pointer" do
    get root_url
    assert_select '.tcg-card[data-tilt]', 3

    get cards_url
    assert_select '.tcg-card'
    assert_select '.tcg-card[data-tilt]', 0
    assert_select '.tcg-card__shine'

    get card_url(cards(:sprigling))
    assert_select '.tcg-card[data-tilt]', 0
  end

  test "the home page and the guide say this is a simulation, not the official game" do
    [root_url, about_url].each do |url|
      get url
      assert_select '.sim-notice h2', /not the official game/
    end
    assert_select 'footer', /simulation for portfolio purposes/
  end
end
