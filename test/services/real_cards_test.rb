require "test_helper"

# Uses the real card data (db/cards.json), so the sample decks and the rules are tried on the cards
# players will actually get. Loading it takes a few seconds, hence few tests.
class RealCardsTest < ActiveSupport::TestCase
  setup do
    CardSnapshot.load(Rails.root.join('db', 'cards.json'))
  end

  test "the sample decks are legal, belong to nobody and use only playable Standard cards" do
    decks = SampleDecks.create!

    assert_equal ['Water starter', 'Grass starter'], decks.map(&:name)
    decks.each do |deck|
      assert deck.legal?, "#{deck.name}: #{deck.problems.inspect}"
      assert_equal 60, deck.card_count
      assert deck.sample?
      assert_nil deck.player
      assert deck.cards.all? { |card| card.playable && card.standard_legal }
      assert deck.cards.any?(&:basic_pokemon?)
    end
  end

  test "evolutions in a sample deck always come with the Pokémon they evolve from" do
    SampleDecks.create!.each do |deck|
      names = deck.cards.map(&:name)

      deck.cards.select { |card| card.pokemon? && card.evolves_from }.each do |card|
        assert_includes names, card.evolves_from, "#{deck.name} has #{card.name} but not #{card.evolves_from}"
      end
    end
  end

  test "building them again changes nothing, and decks that are no longer samples are removed" do
    SampleDecks.create!
    Deck.create!(sample: true, name: 'Old sample')
    assert_equal 3, Deck.samples.count

    SampleDecks.create! # removes the old one

    assert_no_difference 'Deck.samples.count' do
      SampleDecks.create!
    end
    assert_equal ['Grass starter', 'Water starter'], Deck.samples.pluck(:name)
    assert_equal 60, Deck.samples.first.deck_cards.sum(:quantity)
  end

  test "random games between the sample decks end properly and never lose a card" do
    decks = SampleDecks.create!.map(&:card_ids)

    10.times do |seed|
      engine = Tcg::Engine.start(decks: decks, rng: Random.new(seed))
      bot = Tcg::RandomBot.new(rng: Random.new(seed))

      until engine.finished?
        seat = engine.seat_to_act
        engine.perform(seat, bot.choose(engine, seat))
        assert_equal [60, 60], [0, 1].map { |s| engine.card_total(s) }
      end

      assert_includes [0, 1], engine.winner, "seed #{seed}"
    end
  end

  test "every real card the game calls playable has an attack that can be paid with its own type" do
    Card.playable.pokemon.find_each do |card|
      usable = card.attacks.reject { |attack| attack['has_effect'] }
      own_type = [card.type] * 6

      assert usable.any? { |attack| Tcg::EnergyCost.payable?(own_type, attack['cost']) },
             "#{card.name} (#{card.tcgdex_id}) can't pay for any of its usable attacks with its own Energy"
    end
  end

  # Decks drawn at random from every card the game can play: trainers, effects and all. Whatever
  # the bot does, no card may get lost and every game must end.
  test "random games between random decks of playable cards end properly and never lose a card" do
    pool = Card.playable.standard.to_a
    pokemon = pool.select(&:pokemon?)
    trainers = pool.select(&:trainer?)
    energy = pool.select(&:basic_energy?)

    random_deck = lambda do |rng|
      basics = pokemon.select(&:basic_pokemon?).sample(4, random: rng)
      ids = (basics + pokemon.sample(10, random: rng) + trainers.sample(12, random: rng)).flat_map { |card| [card.id] * (card.basic_energy? ? 1 : [rng.rand(1..3), card.ace_spec ? 1 : 4].min) }
      ids = ids.first(50)
      ids << energy.sample(random: rng).id while ids.size < 60
      ids
    end

    20.times do |seed|
      rng = Random.new(seed)
      engine = Tcg::Engine.start(decks: [random_deck.call(rng), random_deck.call(rng)], rng: Random.new(seed))
      bot = Tcg::RandomBot.new(rng: Random.new(seed))
      moves = 0

      until engine.finished?
        seat = engine.seat_to_act
        action = bot.choose(engine, seat)
        engine.perform(seat, action)
        assert_equal [60, 60], [0, 1].map { |s| engine.card_total(s) }, "seed #{seed}, after #{action.inspect}"
        assert_operator (moves += 1), :<, 6000, "seed #{seed} doesn't end"
      end
    end
  end
end
