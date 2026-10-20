require "test_helper"

class DeckTest < ActiveSupport::TestCase
  setup do
    @player = Player.create!
    @deck = @player.decks.create!(name: 'Fresh')
  end

  test "a deck needs a name" do
    assert_not @player.decks.new(name: '').valid?
    assert_not @player.decks.new(name: 'x' * 41).valid?
  end

  test "an empty deck explains what is missing" do
    problems = @deck.problems

    assert_includes problems, 'A deck has exactly 60 cards (this one has 0).'
    assert_includes problems, 'A deck needs at least 1 Basic Pokémon.'
    assert_not @deck.legal?
  end

  test "a full deck of playable Standard cards is legal" do
    deck = build_legal_deck

    assert_equal 60, deck.card_count
    assert_equal [], deck.problems
    assert deck.legal?
  end

  test "more than 4 copies of a card is a problem, but not for basic Energy" do
    deck = build_legal_deck
    deck.deck_cards.find_by!(card: cards(:sprigling)).update!(quantity: 5)
    deck.deck_cards.find_by!(card: cards(:fire_energy)).update!(quantity: 21)

    assert_equal ['At most 4 copies of Sprigling (this deck has 5).'], deck.problems
  end

  test "printings of the same card count together" do
    reprint = cards(:sprigling).dup.tap { |card| card.update!(tcgdex_id: 'test1-901', number: '901') }
    deck = @player.decks.create!(name: 'Reprints')
    deck.deck_cards.create!(card: cards(:sprigling), quantity: 3)
    deck.deck_cards.create!(card: reprint, quantity: 2)

    assert_includes deck.problems, 'At most 4 copies of Sprigling (this deck has 5).'
  end

  test "cards that are not legal or not playable are listed" do
    @deck.deck_cards.create!(card: cards(:retired_pup), quantity: 1)
    @deck.deck_cards.create!(card: cards(:mega_rexor), quantity: 1)

    assert_includes @deck.problems, 'Not legal in Standard: Retired Pup.'
    assert_includes @deck.problems, 'Not playable here yet: Mega Rexor ex.'
  end

  test "only one ACE SPEC card is allowed" do
    ace_one = cards(:sprigling).dup.tap { |card| card.update!(tcgdex_id: 'test1-902', number: '902', name: 'Ace One', ace_spec: true) }
    ace_two = cards(:sprigling).dup.tap { |card| card.update!(tcgdex_id: 'test1-903', number: '903', name: 'Ace Two', ace_spec: true) }
    @deck.deck_cards.create!(card: ace_one, quantity: 1)
    @deck.deck_cards.create!(card: ace_two, quantity: 1)

    assert_includes @deck.problems, 'Only 1 ACE SPEC card is allowed (this deck has 2).'
  end

  test "adding a card puts it in the deck and counts copies" do
    assert @deck.add_card(cards(:sprigling)).ok?
    assert @deck.add_card(cards(:sprigling)).ok?

    assert_equal 2, @deck.quantity_of(cards(:sprigling))
    assert_equal 2, @deck.card_count
  end

  test "the fifth copy is refused" do
    4.times { @deck.add_card(cards(:sprigling)) }

    change = @deck.add_card(cards(:sprigling))

    assert_not change.ok?
    assert_match(/at most 4 copies of Sprigling/, change.message)
    assert_equal 4, @deck.quantity_of(cards(:sprigling))
  end

  test "basic Energy can be added without limit up to the deck size" do
    60.times { assert @deck.add_card(cards(:grass_energy)).ok? }

    change = @deck.add_card(cards(:fire_energy))

    assert_not change.ok?
    assert_match(/already has 60 cards/, change.message)
  end

  test "cards that can't be played or aren't legal can't be added" do
    assert_not @deck.add_card(cards(:mega_rexor)).ok?
    assert_not @deck.add_card(cards(:healing_item)).ok?
    assert_not @deck.add_card(cards(:retired_pup)).ok?
    assert_equal 0, @deck.card_count
  end

  test "a second ACE SPEC card is refused" do
    ace_one = cards(:sprigling).dup.tap { |card| card.update!(tcgdex_id: 'test1-902', number: '902', name: 'Ace One', ace_spec: true) }
    ace_two = cards(:sprigling).dup.tap { |card| card.update!(tcgdex_id: 'test1-903', number: '903', name: 'Ace Two', ace_spec: true) }

    assert @deck.add_card(ace_one).ok?
    assert_not @deck.add_card(ace_two).ok?
  end

  test "card_ids lists one id per physical card" do
    deck = build_legal_deck

    assert_equal 60, deck.card_ids.size
    assert_equal 4, deck.card_ids.count(cards(:sprigling).id)
    assert_equal 22, deck.card_ids.count(cards(:fire_energy).id)
  end

  test "a copy of a deck is the guest's own and can be changed" do
    original = build_legal_deck
    guest = Player.create!

    copy = original.duplicate_for(guest)

    assert_equal guest, copy.player
    assert_equal 'Test deck copy', copy.name
    assert_equal original.card_ids.sort, copy.card_ids.sort
    copy.remove_card(cards(:sprigling))
    assert_equal 4, original.reload.quantity_of(cards(:sprigling))
  end

  test "the name of a copy stays within the limit" do
    deck = @player.decks.create!(name: 'x' * 40)

    assert_equal 40, deck.duplicate_for(@player).name.size
  end

  test "a sample deck belongs to nobody, any other deck needs a player" do
    sample = Deck.new(name: 'Sample', sample: true)

    assert sample.valid?
    assert_not Deck.new(name: 'Orphan').valid?
    assert_includes Deck.samples, Deck.create!(name: 'Sample', sample: true)
    assert_not_includes Deck.samples, @deck
  end

  test "pokemon_names lists each Pokémon once" do
    deck = build_legal_deck

    assert_equal %w[Bloomling Emberpup Shellpal Sprigling], deck.pokemon_names.sort
  end

  test "removing a card takes one copy, then the card" do
    2.times { @deck.add_card(cards(:sprigling)) }

    assert @deck.remove_card(cards(:sprigling)).ok?
    assert_equal 1, @deck.quantity_of(cards(:sprigling))

    assert @deck.remove_card(cards(:sprigling)).ok?
    assert_equal 0, @deck.quantity_of(cards(:sprigling))
    assert_not @deck.remove_card(cards(:sprigling)).ok?
  end
end
