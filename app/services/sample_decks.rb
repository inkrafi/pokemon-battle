# Two decks that are ready to play, built from the cards the game can play. They belong to
# nobody: a guest copies one to get a deck without building it first.
#
# Each deck is one type: the strongest complete evolution lines, a few more Basic Pokemon, and
# basic Energy of that type for the rest.
class SampleDecks
  # Water and Grass make the most even match of the types that have decks: 100 random games, with
  # the first player alternating, ended 52 to 48. (Fire against Psychic was 37 to 63.)
  RECIPES = [{ name: 'Water starter', type: 'Water' }, { name: 'Grass starter', type: 'Grass' }].freeze
  # Plain Trainer cards that suit any deck: a draw Supporter, searching, switching, healing.
  TRAINERS = [["Lillie's Determination", 3], ["Boss's Orders", 2], ['Pokémon Center Lady', 2], ['Buddy-Buddy Poffin', 4],
              ['Ultra Ball', 3], ['Switch', 3], ['Night Stretcher', 2], ['Jumbo Ice Cream', 1]].freeze
  POKEMON_TARGET = 24
  MAX_LINES = 3

  # Builds (or rebuilds) the sample decks. Safe to run again.
  def self.create!
    Deck.where(sample: true).where.not(name: RECIPES.map { |recipe| recipe[:name] }).destroy_all
    RECIPES.map { |recipe| new(**recipe).build! }
  end

  def initialize(name:, type:)
    @name = name
    @type = type
  end

  def build!
    deck = Deck.find_or_create_by!(sample: true, name: @name)
    deck.deck_cards.destroy_all

    plan.each { |card, copies| copies.times { deck.add_card(card) } }
    trainer_package.each { |card, copies| copies.times { deck.add_card(card) } }
    energy = Card.playable.standard.energies.of_type(@type).first
    raise "No basic #{@type} Energy card to finish the deck" unless energy

    deck.add_card(energy) while deck.card_count < Deck::SIZE
    raise "#{@name} isn't legal: #{deck.problems.first}" unless deck.legal?

    deck
  end

  private

  # The Trainer cards every sample deck plays: [[card, copies], ...] for the ones the game can play.
  def trainer_package
    TRAINERS.filter_map do |name, copies|
      card = Card.playable.standard.trainers.where(name: name).order(:id).first
      [card, copies] if card
    end
  end

  # [[card, copies], ...] in the order they are added.
  def plan
    basics = pool.select { |card| card.subtype == 'basic' }
    lines = evolution_lines(basics).first(MAX_LINES)

    wanted = lines.flat_map { |line| line.zip([4, 3, 2]) }
    in_lines = wanted.map { |card, _| card.name }
    extras = basics.reject { |card| in_lines.include?(card.name) }.sort_by { |card| -strength(card) }

    plan = wanted.dup
    extras.each do |card|
      break if plan.sum { |_, copies| copies } >= POKEMON_TARGET

      plan << [card, 3]
    end
    plan
  end

  # One printing per name (the one with the strongest usable attack), of this deck's type.
  def pool
    @pool ||= Card.playable.standard.pokemon.where('cards.energy_types[1] = ?', @type)
                  .group_by(&:name).values.map { |printings| printings.max_by { |card| strength(card) } }
  end

  # Complete lines, strongest first: [basic, stage 1] or [basic, stage 1, stage 2].
  def evolution_lines(basics)
    lines = basics.flat_map do |basic|
      pool.select { |card| card.subtype == 'stage1' && card.evolves_from == basic.name }.map do |stage1|
        stage2 = pool.find { |card| card.subtype == 'stage2' && card.evolves_from == stage1.name }
        [basic, stage1, stage2].compact
      end
    end
    lines.sort_by { |line| -line.sum { |card| strength(card) } }
  end

  # The damage of the best attack the game can play, a little less for a bigger cost.
  def strength(card)
    usable = card.attacks.reject { |attack| attack['has_effect'] || attack['damage'].nil? }
    usable.map { |attack| attack['damage'] - (attack['cost'].size * 5) }.max.to_i + card.hp.to_i / 10
  end
end
