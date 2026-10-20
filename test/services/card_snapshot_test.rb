require "test_helper"
require "tmpdir"

class CardSnapshotTest < ActiveSupport::TestCase
  test "a dump can be loaded into an empty database" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cards.json')
      count = CardSnapshot.dump(path)
      expected = Card.count
      assert_equal expected, count

      DeckCard.delete_all
      Card.delete_all
      CardSet.delete_all

      assert_equal expected, CardSnapshot.load(path)
      assert_equal expected, Card.count
      assert_equal 1, CardSet.count
    end
  end

  test "the data survives the round trip" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cards.json')
      CardSnapshot.dump(path)
      before = cards(:shellpal).attributes.slice('name', 'hp', 'energy_types', 'attacks', 'prize_value', 'standard_legal')

      DeckCard.delete_all
      Card.delete_all
      CardSnapshot.load(path)

      assert_equal before, Card.find_by!(tcgdex_id: 'test1-004').attributes.slice(*before.keys)
    end
  end

  test "loading twice doesn't duplicate anything" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cards.json')
      CardSnapshot.dump(path)

      assert_no_difference ['Card.count', 'CardSet.count'] do
        2.times { CardSnapshot.load(path) }
      end
    end
  end

  test "the snapshot holds no artwork or official text" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'cards.json')
      CardSnapshot.dump(path)
      keys = JSON.parse(File.read(path))['cards'].flat_map(&:keys).uniq

      assert_empty keys & %w[image illustrator description effect flavor_text]
    end
  end
end
