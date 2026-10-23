module Tcgdex
  # Turns a TCGdex card payload into attributes for Card.
  # Only facts are copied, plus a link to the card picture hosted by TCGdex. Flavour text and
  # the wording of effects are left behind:
  # an attack keeps what it does as operations (see Tcg::EffectParser), or has_effect when
  # the engine can't do it yet. The wording itself is never stored.
  class CardMapper
    SUPERTYPES = { 'Pokemon' => 'pokemon', 'Trainer' => 'trainer', 'Energy' => 'energy' }.freeze
    STAGES = { 'Basic' => 'basic', 'Stage1' => 'stage1', 'Stage2' => 'stage2' }.freeze
    # Prize cards given up when a Pokemon with this rule box is Knocked Out.
    PRIZES = { 'ex' => 2, 'EX' => 2, 'V' => 2, 'VSTAR' => 2, 'GX' => 2, 'VMAX' => 3 }.freeze

    def self.call(payload)
      new(payload).attributes
    end

    def initialize(payload)
      @payload = payload
    end

    def attributes
      supertype = SUPERTYPES[@payload['category']]
      raise UnsupportedCard, "Unknown category #{@payload['category'].inspect}" unless supertype

      common.merge(supertype: supertype).merge(send("#{supertype}_attributes"))
    end

    private

    def common
      {
        tcgdex_id: @payload.fetch('id'),
        number: @payload['localId'].to_s,
        name: @payload.fetch('name'),
        rarity: @payload['rarity'],
        regulation_mark: @payload['regulationMark'],
        standard_legal: @payload.dig('legal', 'standard') == true,
        image_url: @payload['image']
      }
    end

    def pokemon_attributes
      weakness = Array(@payload['weaknesses']).first
      resistance = Array(@payload['resistances']).first

      {
        subtype: STAGES.fetch(@payload['stage'].to_s, @payload['stage'].to_s.downcase),
        hp: @payload['hp'],
        energy_types: Array(@payload['types']),
        evolves_from: @payload['evolveFrom'],
        retreat_cost: @payload['retreat'].to_i,
        weakness_type: weakness && weakness['type'],
        weakness_multiplier: weakness && weakness['value'].to_s[/\d+/].to_i,
        resistance_type: resistance && resistance['type'],
        resistance_amount: resistance && resistance['value'].to_s[/\d+/].to_i,
        prize_value: prize_value,
        ace_spec: ace_spec?,
        attacks: Array(@payload['attacks']).map { |attack| map_attack(attack) },
        abilities: Array(@payload['abilities']).map { |ability| map_ability(ability) }
      }
    end

    # An Ability the engine understands carries its operations; any other is kept by name only
    # and keeps its Pokémon out of play.
    def map_ability(ability)
      base = { 'name' => ability['name'], 'kind' => ability['type'] }
      parsed = ability['type'] == 'Ability' ? Tcg::EffectParser.ability(ability['effect']) : nil
      parsed ? base.merge(parsed).merge('supported' => true) : base.merge('supported' => false)
    end

    def trainer_attributes
      { subtype: @payload['trainerType'].to_s.downcase, ace_spec: ace_spec?,
        effects: Tcg::EffectParser.trainer(@payload['effect']) || [] }
    end

    # Only a plain "<Type> Energy" is basic. TCGdex also marks some special Energy as "Normal",
    # so the name decides, not the flag.
    BASIC_ENERGY = /\A(?:Basic )?(Grass|Fire|Water|Lightning|Psychic|Fighting|Darkness|Metal) Energy\z/

    def energy_attributes
      type = @payload['name'].to_s[BASIC_ENERGY, 1]
      return { subtype: 'special', energy_types: [] } unless type && @payload['energyType'] == 'Normal'

      { subtype: 'basic', energy_types: [type] }
    end

    def prize_value
      return 3 if @payload['suffix'] == 'ex' && @payload['name'].to_s.start_with?('Mega ')

      PRIZES.fetch(@payload['suffix'].to_s, 1)
    end

    def ace_spec?
      @payload['rarity'].to_s.include?('ACE SPEC')
    end

    # Damage can be 30, "30+", "30x" or "30-": the number and the modifier are kept apart.
    def map_attack(attack)
      damage = attack['damage']
      amount = damage.to_s[/\d+/]&.to_i
      modifier = damage.to_s.sub(/\A\d*/, '').strip.tr('x', "×").presence
      effects = Tcg::EffectParser.attack(attack['effect'])

      {
        'name' => attack['name'],
        'cost' => Array(attack['cost']),
        'damage' => amount,
        'modifier' => modifier,
        'has_effect' => effects.nil?, # true: there is an effect that isn't understood yet
        'effects' => effects || []
      }
    end
  end
end
