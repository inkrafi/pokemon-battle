require "test_helper"

class DecksControllerTest < ActionDispatch::IntegrationTest
  def create_deck(name = 'Mine')
    post decks_url, params: { deck: { name: name } }
    Deck.order(:id).last
  end

  test "a visitor becomes a guest the first time they start a deck" do
    assert_difference 'Player.count', 1 do
      create_deck
    end

    assert cookies[:player_token].present?
  end

  test "the same browser keeps the same guest" do
    assert_difference 'Player.count', 1 do
      create_deck('One')
      create_deck('Two')
    end

    assert_equal 2, Deck.where(player: Player.last).count
  end

  test "the deck list is empty before anything is created" do
    get decks_url

    assert_response :success
    assert_select '.empty-state', /No decks yet/
  end

  test "creating a deck opens the builder" do
    deck = create_deck('Fire rush')

    assert_redirected_to deck_url(deck)
    follow_redirect!
    assert_select 'h2#deck-heading', 'Fire rush'
  end

  test "a deck without a name is refused" do
    assert_no_difference 'Deck.count' do
      post decks_url, params: { deck: { name: '' } }
    end

    assert_response :unprocessable_entity
    assert_select '.error-summary'
  end

  test "the deck list shows the progress of each deck" do
    deck = create_deck('Mine')
    deck.add_card(cards(:sprigling))

    get decks_url

    assert_select '.deck-row h2', 'Mine'
    assert_select '.deck-row p', /1 card of 60/
    assert_select '.status-chip', 'Needs work'
  end

  test "a legal deck is marked ready" do
    deck = build_legal_deck(player: create_deck.player)

    get decks_url

    assert_equal 60, deck.card_count
    assert_select '.status-chip--ok', 'Ready to play'
  end

  test "the builder shows the count, the problems and the cards of the deck" do
    deck = create_deck
    2.times { deck.add_card(cards(:sprigling)) }

    get deck_url(deck)

    assert_select '.deck-meter__label', /2 \/ 60/
    assert_select '.problems li', /exactly 60 cards/
    assert_select '.deck-entry__name', /Sprigling/
    assert_select '.deck-entry__qty span', '2'
  end

  test "the builder only offers cards that can be added" do
    deck = create_deck

    get deck_url(deck)

    names = css_select('.pool-card .tcg-card__name').map { |node| node.text.strip }
    assert_includes names, 'Sprigling'
    assert_not_includes names, 'Mega Rexor ex'  # not playable
    assert_not_includes names, 'Retired Pup'    # not Standard legal
    assert_not_includes names, 'Healing Salve'  # Trainer
  end

  test "the builder card list can be searched" do
    deck = create_deck

    get deck_url(deck), params: { q: 'shell' }

    assert_select '.pool-card', 1
    assert_select '.pool-card .tcg-card__name', 'Shellpal'
  end

  test "the builder card list can be filtered by kind and type" do
    deck = create_deck

    get deck_url(deck), params: { supertype: 'energy', type: 'Fire' }

    assert_select '.pool-card', 1
    assert_select '.pool-card .tcg-card__name', 'Fire Energy'
  end

  test "a deck that is full and legal says so" do
    deck = build_legal_deck(player: create_deck.player)

    get deck_url(deck)

    assert_select '.problems--ready', /legal and ready to play/
    assert_select '.deck-meter__bar.is-full'
  end

  test "the deck list offers the sample decks" do
    sample = Deck.create!(name: 'Starter', sample: true)
    sample.add_card(cards(:sprigling))

    get decks_url

    assert_select '#samples-heading', 'Sample decks'
    assert_select '.deck-row h3', 'Starter'
    assert_select 'form[action=?]', copy_deck_path(sample)
  end

  test "there is no sample section when there are no samples" do
    get decks_url

    assert_select '#samples-heading', 0
  end

  test "copying a sample deck gives the guest a deck of their own" do
    sample = Deck.create!(name: 'Starter', sample: true)
    sample.add_card(cards(:sprigling))

    assert_difference 'Deck.count', 1 do
      post copy_deck_url(sample)
    end

    copy = Deck.order(:id).last
    assert_redirected_to deck_url(copy)
    assert_equal 'Starter copy', copy.name
    assert_equal 1, copy.quantity_of(cards(:sprigling))
    assert_not copy.sample?
    assert_equal Player.last, copy.player
    assert_equal 1, sample.reload.card_count # the sample itself is untouched
  end

  test "a guest can copy their own deck" do
    deck = create_deck('Mine')

    assert_difference 'Deck.count', 1 do
      post copy_deck_url(deck)
    end

    assert_equal 'Mine copy', Deck.order(:id).last.name
  end

  test "somebody else's deck can't be copied" do
    create_deck
    stranger = Deck.create!(player: Player.create!, name: 'Not yours')

    assert_no_difference 'Deck.count' do
      assert_raises(ActiveRecord::RecordNotFound) { post copy_deck_url(stranger) }
    end
  end

  test "a deck can be renamed" do
    deck = create_deck('Old name')

    patch deck_url(deck), params: { deck: { name: 'New name' } }

    assert_redirected_to deck_url(deck)
    assert_equal 'New name', deck.reload.name
  end

  test "renaming to nothing is refused" do
    deck = create_deck('Keep me')

    patch deck_url(deck), params: { deck: { name: '' } }

    assert_equal 'Keep me', deck.reload.name
    assert flash[:danger].present?
  end

  test "a deck can be deleted with its cards" do
    deck = create_deck
    deck.add_card(cards(:sprigling))

    assert_difference ['Deck.count', 'DeckCard.count'], -1 do
      delete deck_url(deck)
    end

    assert_redirected_to decks_url
  end

  test "somebody else's deck can't be opened, changed or deleted" do
    create_deck
    stranger = Deck.create!(player: Player.create!, name: 'Not yours')

    assert_raises(ActiveRecord::RecordNotFound) { get deck_url(stranger) }
    assert_raises(ActiveRecord::RecordNotFound) { patch deck_url(stranger), params: { deck: { name: 'Mine now' } } }
    assert_raises(ActiveRecord::RecordNotFound) { delete deck_url(stranger) }
    assert_equal 'Not yours', stranger.reload.name
  end

  test "somebody else's deck doesn't show up in the list" do
    create_deck('Mine')
    Deck.create!(player: Player.create!, name: 'Not yours')

    get decks_url

    assert_select '.deck-row h2', 'Mine'
    assert_select '.deck-row h2', text: 'Not yours', count: 0
  end
end
