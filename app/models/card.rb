# One printed card: a Pokemon, a Trainer or an Energy. Only game facts are stored.
class Card < ApplicationRecord
  SUPERTYPES = %w[pokemon trainer energy].freeze
  # The ten types of the card game.
  TYPES = %w[Grass Fire Water Lightning Psychic Fighting Darkness Metal Dragon Colorless].freeze
  STAGE_LABELS = { 'basic' => 'Basic', 'stage1' => 'Stage 1', 'stage2' => 'Stage 2' }.freeze

  belongs_to :card_set
  has_many :deck_cards, dependent: :restrict_with_error

  scope :pokemon,  -> { where(supertype: 'pokemon') }
  scope :trainers, -> { where(supertype: 'trainer') }
  scope :energies, -> { where(supertype: 'energy') }
  scope :playable, -> { where(playable: true) }
  scope :standard, -> { where(standard_legal: true) }
  scope :named_like, ->(text) { where('cards.name ILIKE ?', "%#{sanitize_sql_like(text)}%") }
  scope :of_type, ->(type) { where('? = ANY (cards.energy_types)', type) }

  before_save { self.playable = engine_ready? }

  validates :tcgdex_id, presence: true, uniqueness: true
  validates :number, :name, presence: true
  validates :supertype, inclusion: { in: SUPERTYPES }
  validates :hp, numericality: { only_integer: true, greater_than: 0 }, if: :pokemon?

  def pokemon?
    supertype == 'pokemon'
  end

  def trainer?
    supertype == 'trainer'
  end

  def energy?
    supertype == 'energy'
  end

  def basic_pokemon?
    pokemon? && subtype == 'basic'
  end

  def basic_energy?
    energy? && subtype == 'basic'
  end

  # The first (usually only) type of a Pokemon, or the type a basic Energy provides.
  def type
    energy_types.first
  end

  def stage_label
    STAGE_LABELS[subtype] || subtype.to_s.titleize
  end

  # "ex" cards give up more Prize cards when Knocked Out.
  def rule_box
    return 'Mega ex' if prize_value >= 3
    return 'ex' if prize_value == 2

    nil
  end

  def attack_names
    attacks.map { |attack| attack['name'] }
  end

  # Whether the game engine can play this card as it is now. A Trainer is played when what it does
  # is known (effects), a Pokémon when all its Abilities and one of its attacks can be run. Cards get playable as more of
  # their effects are implemented, see lib/tasks/cards.rake (cards:refresh_playable).
  def engine_ready?
    case supertype
    when 'pokemon'
      hp.to_i.positive? && abilities.all? { |ability| ability['supported'] } && attacks.any? { |attack| !attack['has_effect'] }
    when 'energy'
      basic_energy? && energy_types.any?
    when 'trainer'
      effects.any?
    else
      false
    end
  end
end
