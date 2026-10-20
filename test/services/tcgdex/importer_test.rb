require "test_helper"

class Tcgdex::ImporterTest < ActiveSupport::TestCase
  # Answers like TCGdex, from memory: no network in tests.
  class FakeClient
    def initialize(sets, cards)
      @sets = sets
      @cards = cards
    end

    def set(id)
      @sets.fetch(id)
    end

    def card(id)
      @cards.fetch(id) { raise Tcgdex::Client::Error, "no #{id}" }
    end
  end

  def card_payload(id, name, standard: true)
    { 'category' => 'Pokemon', 'id' => id, 'localId' => id[-3..], 'name' => name, 'hp' => 60, 'types' => ['Fire'], 'stage' => 'Basic',
      'legal' => { 'standard' => standard }, 'attacks' => [{ 'name' => 'Poke', 'cost' => ['Fire'], 'damage' => 10 }] }
  end

  def client
    FakeClient.new(
      { 'zz9' => { 'id' => 'zz9', 'name' => 'Imported Set', 'releaseDate' => '2025-05-05', 'cardCount' => { 'official' => 3 },
                   'cards' => [{ 'id' => 'zz9-001' }, { 'id' => 'zz9-002' }, { 'id' => 'zz9-003' }] } },
      { 'zz9-001' => card_payload('zz9-001', 'Importmon'),
        'zz9-002' => card_payload('zz9-002', 'Oldmon', standard: false) }
    )
  end

  test "imports the cards of a set" do
    result = Tcgdex::Importer.new(client: client).import_sets(['zz9'])

    assert_equal 1, result.sets
    assert_equal 1, result.cards
    assert_equal 'Imported Set', CardSet.find_by!(tcgdex_id: 'zz9').name
    card = Card.find_by!(tcgdex_id: 'zz9-001')
    assert_equal ['Importmon', 'zz9'], [card.name, card.card_set.tcgdex_id]
    assert card.playable
  end

  test "leaves out cards that are not Standard legal unless asked" do
    result = Tcgdex::Importer.new(client: client).import_sets(['zz9'])
    assert_equal 1, result.skipped
    assert_nil Card.find_by(tcgdex_id: 'zz9-002')

    Tcgdex::Importer.new(client: client).import_sets(['zz9'], standard_only: false)
    assert Card.exists?(tcgdex_id: 'zz9-002')
  end

  test "a card that can't be fetched is reported, the rest still imported" do
    result = Tcgdex::Importer.new(client: client).import_sets(['zz9'])

    assert_equal 1, result.failed.size
    assert_match(/zz9-003/, result.failed.first)
    assert Card.exists?(tcgdex_id: 'zz9-001')
  end

  test "running it again updates instead of duplicating" do
    2.times { Tcgdex::Importer.new(client: client).import_sets(['zz9']) }

    assert_equal 1, Card.where(tcgdex_id: 'zz9-001').count
    assert_equal 1, CardSet.where(tcgdex_id: 'zz9').count
  end

  test "reports progress to the logger" do
    lines = []
    Tcgdex::Importer.new(client: client, logger: ->(line) { lines << line }).import_sets(['zz9'])

    assert_equal ['Imported Set: 3 cards'], lines
  end
end
