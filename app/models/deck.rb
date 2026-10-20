# A 60 card deck. Rules follow the Standard format of the card game.
class Deck < ApplicationRecord
  SIZE = 60
  MAX_COPIES = 4

  belongs_to :player, optional: true # sample decks belong to nobody
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards

  validates :name, presence: true, length: { maximum: 40 }
  validates :player, presence: true, unless: :sample?

  scope :samples, -> { where(sample: true).order(:name) }

  # Result of adding or removing a card: ok? plus a message when it was refused.
  Change = Struct.new(:ok, :message) do
    def ok? = ok
  end

  def card_count
    deck_cards.sum(&:quantity)
  end

  # The distinct Pokémon in the deck, for a short description.
  def pokemon_names
    deck_cards.map(&:card).select(&:pokemon?).map(&:name).uniq
  end

  # One Card id per physical card, for starting a game.
  def card_ids
    deck_cards.sort_by(&:id).flat_map { |entry| [entry.card_id] * entry.quantity }
  end

  # A copy a guest can edit, from a sample deck or one of their own.
  def duplicate_for(player)
    copy = player.decks.create!(name: "#{name} copy".first(40))
    deck_cards.each { |entry| copy.deck_cards.create!(card_id: entry.card_id, quantity: entry.quantity) }
    copy
  end

  def quantity_of(card)
    deck_cards.find { |deck_card| deck_card.card_id == card.id }&.quantity.to_i
  end

  # Copies per card name (printings of the same card count together).
  def copies_by_name
    deck_cards.includes(:card).group_by { |deck_card| deck_card.card.name }
              .transform_values { |entries| entries.sum(&:quantity) }
  end

  # Why this deck can't be played yet. Empty when it is legal.
  def problems
    entries = deck_cards.includes(:card).to_a
    messages = []

    total = entries.sum(&:quantity)
    messages << "A deck has exactly #{SIZE} cards (this one has #{total})." if total != SIZE
    messages << 'A deck needs at least 1 Basic Pokémon.' unless entries.any? { |entry| entry.card.basic_pokemon? }

    copies = entries.reject { |entry| entry.card.basic_energy? }.group_by { |entry| entry.card.name }
    copies.each do |name, group|
      messages << "At most #{MAX_COPIES} copies of #{name} (this deck has #{group.sum(&:quantity)})." if group.sum(&:quantity) > MAX_COPIES
    end

    ace_specs = entries.select { |entry| entry.card.ace_spec }.sum(&:quantity)
    messages << "Only 1 ACE SPEC card is allowed (this deck has #{ace_specs})." if ace_specs > 1

    illegal = entries.reject { |entry| entry.card.standard_legal }.map { |entry| entry.card.name }.uniq
    messages << "Not legal in Standard: #{illegal.to_sentence}." if illegal.any?

    unplayable = entries.reject { |entry| entry.card.playable }.map { |entry| entry.card.name }.uniq
    messages << "Not playable here yet: #{unplayable.to_sentence}." if unplayable.any?

    messages
  end

  def legal?
    problems.empty?
  end

  def add_card(card)
    return Change.new(false, "#{card.name} can't be played here yet.") unless card.playable
    return Change.new(false, "#{card.name} isn't legal in Standard.") unless card.standard_legal
    return Change.new(false, "The deck already has #{SIZE} cards.") if card_count >= SIZE

    unless card.basic_energy?
      by_name = copies_by_name[card.name].to_i
      return Change.new(false, "A deck can have at most #{MAX_COPIES} copies of #{card.name}.") if by_name >= MAX_COPIES
      if card.ace_spec && deck_cards.includes(:card).any? { |entry| entry.card.ace_spec }
        return Change.new(false, 'A deck can have only 1 ACE SPEC card.')
      end
    end

    entry = deck_cards.find_or_initialize_by(card: card)
    entry.quantity = entry.new_record? ? 1 : entry.quantity + 1
    entry.save!
    deck_cards.reset
    Change.new(true, nil)
  end

  def remove_card(card)
    entry = deck_cards.find_by(card: card)
    return Change.new(false, "#{card.name} isn't in the deck.") unless entry

    entry.quantity > 1 ? entry.update!(quantity: entry.quantity - 1) : entry.destroy!
    deck_cards.reset
    Change.new(true, nil)
  end
end
