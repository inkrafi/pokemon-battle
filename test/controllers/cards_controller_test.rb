require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  test "index lists the cards" do
    get cards_url

    assert_response :success
    assert_select '.tcg-card', Card.count
    assert_select '.result-count', /#{Card.count} cards/
  end

  test "index searches by name, ignoring case" do
    get cards_url, params: { q: 'EMBER' }

    assert_select '.tcg-card__name', 'Emberpup'
    assert_select '.tcg-card', 1
  end

  test "index filters by kind of card" do
    get cards_url, params: { supertype: 'energy' }

    assert_select '.tcg-card', 3
    assert_select '.tcg-card__stage', text: /Basic Energy/, count: 3
  end

  test "index filters by type" do
    get cards_url, params: { type: 'Water' }

    assert_select '.tcg-card__name', text: 'Shellpal'
    assert_select '.tcg-card__name', text: 'Water Energy'
    assert_select '.chip.is-active', /Water/
  end

  test "index filters by set" do
    other = CardSet.create!(tcgdex_id: 'test2', name: 'Other Set')
    Card.create!(card_set: other, tcgdex_id: 'test2-001', number: '001', name: 'Elsewhere', supertype: 'energy', subtype: 'basic', energy_types: ['Fire'])

    get cards_url, params: { set: other.id }

    assert_select '.tcg-card', 1
    assert_select '.tcg-card__name', 'Elsewhere'
  end

  test "index can show only the cards that can be played" do
    get cards_url, params: { playable: '1' }

    assert_select '.tcg-card__name', text: 'Mega Rexor ex', count: 0
    assert_select '.tcg-card__name', text: 'Healing Salve', count: 0
    assert_select '.tcg-card', Card.playable.count
  end

  test "index ignores filter values it doesn't know" do
    get cards_url, params: { supertype: 'weapon', type: 'Sound' }

    assert_response :success
    assert_select '.tcg-card', Card.count
  end

  test "index explains when nothing matches" do
    get cards_url, params: { q: 'zzz' }

    assert_select '.empty-state', /No cards match/
  end

  test "a Pokémon card shows what the real card shows" do
    get card_url(cards(:shellpal))

    assert_response :success
    assert_select '.tcg-card__name', 'Shellpal'
    assert_select '.tcg-hp strong', '70'
    assert_select '.tcg-attack__name', /Splash/
    assert_select '.tcg-attack__damage', '20'
    assert_select '.tcg-attack__damage', "50+"
    assert_select '.tcg-card__foot', /Weakness/
    assert_select '.tcg-card__foot', /Retreat/
  end

  test "an attack with an effect is flagged" do
    get card_url(cards(:shellpal))

    assert_select '.tcg-attack__flag', 1
  end

  test "a Mega ex card tells how many Prize cards it gives up" do
    get card_url(cards(:mega_rexor))

    assert_select '.tcg-card__rulebox', /Mega ex/
    assert_select '.tcg-card__rulebox', /3 Prize cards/
    assert_select '.tcg-attack--ability', /Frenzy/
  end

  test "card artwork and official text are not shown" do
    get card_url(cards(:sprigling))

    assert_select '.tcg-card img', 0
  end

  test "the card page says why a card can't be played" do
    get card_url(cards(:mega_rexor))
    assert_select 'p', /Ability/

    get card_url(cards(:healing_item))
    assert_select 'p', /What this Trainer card does isn't available in play yet/
  end

  test "a playable card offers to start a deck for a visitor without one" do
    get card_url(cards(:sprigling))

    assert_select 'a', 'Start a deck'
    assert_equal 0, Player.count
  end

  test "a playable card can be added to the visitor's decks" do
    post decks_url, params: { deck: { name: 'Mine' } }
    deck = Deck.last

    get card_url(cards(:sprigling))

    assert_select 'form[action=?]', add_card_deck_path(deck, card_id: cards(:sprigling).id)
  end

  test "a card that can't be played has no add button" do
    post decks_url, params: { deck: { name: 'Mine' } }

    get card_url(cards(:mega_rexor))

    assert_select 'form[action*="/cards/"]', 0
  end
end
