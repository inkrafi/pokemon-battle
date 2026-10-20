require "test_helper"

class DeckCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    post decks_url, params: { deck: { name: 'Mine' } }
    @deck = Deck.order(:id).last
  end

  test "adding a card puts it in the deck and goes back" do
    post add_card_deck_url(@deck, card_id: cards(:sprigling).id), headers: { 'HTTP_REFERER' => deck_url(@deck, q: 'sprig') }

    assert_redirected_to deck_url(@deck, q: 'sprig')
    assert_equal 1, @deck.quantity_of(cards(:sprigling))
  end

  test "without a referrer it goes to the builder" do
    post add_card_deck_url(@deck, card_id: cards(:sprigling).id)

    assert_redirected_to deck_url(@deck)
  end

  test "a refused card says why" do
    post add_card_deck_url(@deck, card_id: cards(:mega_rexor).id)

    assert_equal 0, @deck.reload.card_count
    assert_match(/can't be played here yet/, flash[:danger])
  end

  test "the fifth copy is refused" do
    4.times { post add_card_deck_url(@deck, card_id: cards(:sprigling).id) }
    post add_card_deck_url(@deck, card_id: cards(:sprigling).id)

    assert_equal 4, @deck.quantity_of(cards(:sprigling))
    assert_match(/at most 4 copies/, flash[:danger])
  end

  test "removing a card takes one copy out" do
    2.times { @deck.add_card(cards(:sprigling)) }

    delete remove_card_deck_url(@deck, card_id: cards(:sprigling).id)

    assert_equal 1, @deck.quantity_of(cards(:sprigling))
  end

  test "removing a card that is not in the deck says so" do
    delete remove_card_deck_url(@deck, card_id: cards(:sprigling).id)

    assert_match(/isn't in the deck/, flash[:danger])
  end

  test "an unknown card is a 404" do
    assert_raises(ActiveRecord::RecordNotFound) { post add_card_deck_url(@deck, card_id: 0) }
  end

  test "another guest's deck can't be changed" do
    stranger = Deck.create!(player: Player.create!, name: 'Not yours')

    assert_raises(ActiveRecord::RecordNotFound) { post add_card_deck_url(stranger, card_id: cards(:sprigling).id) }
    assert_equal 0, stranger.reload.card_count
  end

  test "the builder buttons work end to end" do
    get deck_url(@deck)
    assert_select '.pool-card form[action=?]', add_card_deck_path(@deck, card_id: cards(:sprigling).id)

    post add_card_deck_url(@deck, card_id: cards(:sprigling).id)
    follow_redirect!

    assert_select '.deck-entry__name', /Sprigling/
    assert_select '.card-count', '1'
  end
end
