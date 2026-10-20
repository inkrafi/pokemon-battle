module Tcg
  # Recognises what an attack, a Trainer or an Ability does and turns it into a short list of
  # operations (plain hashes) that the engine can run. The printed wording is only read here,
  # while importing; what gets stored is the operations, never the text.
  #
  # A text is understood only when every sentence in it is: a card that is half understood
  # would play wrongly, so it is left out of play instead (parse returns nil).
  #
  #   Tcg::EffectParser.attack("Flip 3 coins. This attack does 30 damage for each heads.")
  #   # => [{ 'op' => 'flip_each', 'coins' => 3, 'per' => 30 }]
  module EffectParser
    TYPE_CODES = { 'G' => 'Grass', 'R' => 'Fire', 'W' => 'Water', 'L' => 'Lightning', 'P' => 'Psychic',
                   'F' => 'Fighting', 'D' => 'Darkness', 'M' => 'Metal', 'N' => 'Dragon', 'C' => 'Colorless' }.freeze
    CONDITION = '(Poisoned|Burned|Asleep|Confused|Paralyzed)'.freeze
    NUMBER_WORDS = { 'a' => 1, 'an' => 1, '1' => 1 }.freeze

    module_function

    # The operations for an attack's effect text, [] when there is none, nil when some of it
    # is not understood.
    def attack(text)
      parse(text, ATTACK_RULES)
    end

    # The operations for a Trainer card's text, [] when there is none, nil when some of it is
    # not understood.
    def trainer(text)
      parse(text, TrainerRules::RULES)
    end

    # An Ability: { 'trigger' => 'passive' | 'activated' | 'on_evolve', 'needs' => {...}, 'effects' => [ops] },
    # nil when some of it is not understood.
    def ability(text)
      text = text.to_s.gsub(/\s+/, ' ').strip
      ABILITY_PREFIXES.each do |pattern, trigger, needs|
        match = text.match(/\A#{pattern}\s*/)
        next unless match

        ops = parse(match.post_match, ABILITY_RULES)
        return ops && { 'trigger' => trigger, 'needs' => needs.call(match), 'effects' => ops }
      end

      ops = parse(text, PASSIVE_RULES)
      ops && { 'trigger' => 'passive', 'needs' => {}, 'effects' => ops }
    end

    # What a search is looking for, from the words used on a card ("Basic {R} Energy card").
    def search_filter(text)
      type = TYPE_CODES[text[/\{([GRWLPFDMNC])\}/, 1]]
      case text.strip
      when /\A(?:Basic )?\{[A-Z]\} Energy cards?\z/ then { 'supertype' => 'energy', 'basic_energy' => true, 'type' => type }
      when /\ABasic Energy cards?\z/ then { 'supertype' => 'energy', 'basic_energy' => true }
      when /\ABasic Pokémon with (\d+) HP or less\z/ then { 'supertype' => 'pokemon', 'subtype' => 'basic', 'max_hp' => Regexp.last_match(1).to_i }
      when /\ABasic Pokémon\z/ then { 'supertype' => 'pokemon', 'subtype' => 'basic' }
      when /\ABasic \{[A-Z]\} Pokémon\z/ then { 'supertype' => 'pokemon', 'subtype' => 'basic', 'type' => type }
      when /\A\{[A-Z]\} Pokémon\z/ then { 'supertype' => 'pokemon', 'type' => type }
      when /\AStage 1 Pokémon\z/ then { 'supertype' => 'pokemon', 'subtype' => 'stage1' }
      when /\AStage 2 Pokémon\z/ then { 'supertype' => 'pokemon', 'subtype' => 'stage2' }
      when /\AMega Evolution Pokémon ex\z/ then { 'supertype' => 'pokemon', 'mega' => true }
      when /\APokémon\z/ then { 'supertype' => 'pokemon' }
      when /\ASupporter card\z/ then { 'supertype' => 'trainer', 'subtype' => 'supporter' }
      end
    end

    # "Basic {F} Energy card or a Basic {F} Pokémon" gives one filter that takes either.
    def search_filters(text)
      options = text.split(/ or (?:a |an )/).map { |part| search_filter(part.sub(/\A(?:a|an) /, '')) }
      return nil if options.empty? || options.any?(&:nil?)

      options.size == 1 ? options.first : { 'any' => options }
    end

    def parse(text, rules)
      rest = text.to_s.gsub(/\s+/, ' ').strip
      ops = []
      until rest.empty?
        match = nil
        rule = rules.find { |pattern, _| (match = rest.match(/\A#{pattern}\s*/)) }
        return nil unless rule

        built = rule.last.call(match)
        return nil if built.nil?

        ops.concat(built.is_a?(Array) ? built : [built])
        rest = match.post_match
      end
      ops
    end

    def count(word)
      NUMBER_WORDS.fetch(word.to_s.downcase) { word.to_i }
    end

    def type_of(code)
      code && TYPE_CODES[code]
    end

    def condition(word)
      word.downcase
    end

    # Defines a rule: +pattern+ is a regexp source matched at the start of what is left.
    def self.rule(pattern, &build)
      [pattern, build]
    end

    TYPE = '(?:\{([GRWLPFDMNC])\} )?'.freeze
    NUM = '(\d+)'.freeze

    ATTACK_RULES = [
      # --- damage that depends on coins
      rule("Flip #{NUM} coins\\. This attack does #{NUM} damage for each heads\\.") { |m| { 'op' => 'flip_each', 'coins' => m[1].to_i, 'per' => m[2].to_i } },
      rule("Flip a coin until you get tails\\. This attack does #{NUM} damage for each heads\\.") { |m| { 'op' => 'flip_until_tails', 'per' => m[1].to_i } },
      rule("Flip a coin until you get tails\\. This attack does #{NUM} more damage for each heads\\.") { |m| { 'op' => 'flip_until_tails', 'per' => m[1].to_i, 'plus' => true } },
      rule("Flip a coin\\. If heads, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'flip_bonus', 'bonus' => m[1].to_i } },
      rule("Flip 2 coins\\. If both of them are heads, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'flip_both_bonus', 'bonus' => m[1].to_i } },
      rule("Flip a coin\\. If tails, this attack does nothing\\.") { |_| { 'op' => 'flip_or_nothing' } },

      # --- damage that depends on the board
      rule("This attack does #{NUM} more damage for each #{TYPE}Energy attached to this Pokémon\\.") { |m| { 'op' => 'plus_per_energy', 'per' => m[1].to_i, 'type' => type_of(m[2]) } },
      rule("This attack does #{NUM} damage for each #{TYPE}Energy attached to all of your Pokémon\\.") { |m| { 'op' => 'per_energy_in_play', 'per' => m[1].to_i, 'type' => type_of(m[2]) } },
      rule("This attack does #{NUM} more damage for each Energy attached to your opponent's Active Pokémon\\.") { |m| { 'op' => 'plus_per_target_energy', 'per' => m[1].to_i } },
      rule("This attack does #{NUM} damage for each damage counter on your opponent's Active Pokémon\\.") { |m| { 'op' => 'per_target_counter', 'per' => m[1].to_i } },
      rule("This attack does #{NUM} damage for each Prize card you have taken\\.") { |m| { 'op' => 'per_prize_taken', 'per' => m[1].to_i } },
      rule("This attack does #{NUM} damage for each of your Pokémon in play\\.") { |m| { 'op' => 'per_own_pokemon', 'per' => m[1].to_i } },
      rule("If this Pokémon has any damage counters on it, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'plus_if_self_damaged', 'bonus' => m[1].to_i } },
      rule("If your opponent's Active Pokémon already has any damage counters on it, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'plus_if_target_damaged', 'bonus' => m[1].to_i } },
      rule("If your opponent's Active Pokémon is #{CONDITION}, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'plus_if_target_condition', 'condition' => condition(m[1]), 'bonus' => m[2].to_i } },
      rule("If your opponent's Active Pokémon is a Pokémon ex, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'plus_if_target_ex', 'bonus' => m[1].to_i } },
      rule("If this Pokémon moved from your Bench to the Active Spot this turn, this attack does #{NUM} more damage\\.") { |m| { 'op' => 'plus_if_moved_up', 'bonus' => m[1].to_i } },
      rule("This attack's damage isn't affected by any effects on your opponent's Active Pokémon\\.") { |_| { 'op' => 'ignore', 'what' => 'effects' } },
      rule("This attack's damage isn't affected by Weakness or Resistance\\.") { |_| { 'op' => 'ignore', 'what' => 'matchup' } },
      rule("This attack's damage isn't affected by Resistance\\.") { |_| { 'op' => 'ignore', 'what' => 'resistance' } },

      rule("If you have exactly #{NUM} Prize cards remaining, this attack does #{NUM} more damage\.") { |m| { 'op' => 'plus_if_own_prizes', 'prizes' => m[1].to_i, 'bonus' => m[2].to_i } },
      rule("If your opponent has #{NUM} or fewer Prize cards remaining, this attack does #{NUM} more damage\.") { |m| { 'op' => 'plus_if_opponent_prizes_at_most', 'prizes' => m[1].to_i, 'bonus' => m[2].to_i } },

      # --- searching the deck
      rule(TrainerRules::SEARCH_TEXT) do |m|
        filter = search_filters(m[3])
        next nil unless filter

        count = m[2] ? m[2].to_i : 1
        { 'op' => 'search', 'filters' => [filter] * count, 'to' => m[4] == 'onto your Bench' ? 'bench' : 'hand' }
      end,
      rule("Search your deck for (a|up to #{NUM}) Basic \{([A-Z])\} Energy cards? and attach (?:it|them) to this Pokémon\. Then, shuffle your deck\.") do |m|
        count = m[2] ? m[2].to_i : 1
        { 'op' => 'search', 'filters' => [{ 'supertype' => 'energy', 'basic_energy' => true, 'type' => type_of(m[3]) }] * count, 'to' => 'self' }
      end,

      # --- Special Conditions
      rule("Your opponent's Active Pokémon is now #{CONDITION} and #{CONDITION}\\.") { |m| [{ 'op' => 'inflict', 'condition' => condition(m[1]) }, { 'op' => 'inflict', 'condition' => condition(m[2]) }] },
      rule("Your opponent's Active Pokémon is now #{CONDITION}\\.") { |m| { 'op' => 'inflict', 'condition' => condition(m[1]) } },
      rule("Flip a coin\\. If heads, your opponent's Active Pokémon is now #{CONDITION}\\.") { |m| { 'op' => 'inflict', 'condition' => condition(m[1]), 'if' => 'heads' } },

      # --- the attacker itself
      rule("Heal #{NUM} damage from this Pokémon\\.") { |m| { 'op' => 'heal_self', 'amount' => m[1].to_i } },
      rule("This Pokémon also does #{NUM} damage to itself\\.") { |m| { 'op' => 'recoil', 'amount' => m[1].to_i } },
      rule("Discard all Energy from this Pokémon\\.") { |_| { 'op' => 'discard_self_energy', 'count' => 'all' } },
      rule("Discard (a|an|#{NUM}) Energy from this Pokémon\\.") { |m| { 'op' => 'discard_self_energy', 'count' => count(m[2] || m[1]) } },
      rule("Switch this Pokémon with 1 of your Benched Pokémon\\.") { |_| { 'op' => 'switch_self' } },
      rule("You may switch this Pokémon with 1 of your Benched Pokémon\\.") { |_| { 'op' => 'switch_self', 'optional' => true } },
      rule("Draw (a|#{NUM}) cards?\\.") { |m| { 'op' => 'draw', 'count' => count(m[2] || m[1]) } },
      rule("You may draw cards until you have #{NUM} cards in your hand\\.") { |m| { 'op' => 'draw_until', 'size' => m[1].to_i } },

      # --- the defender
      rule("Switch out your opponent's Active Pokémon to the Bench\\. \\(Your opponent chooses the new Active Pokémon\\.\\)") { |_| { 'op' => 'switch_opponent' } },
      rule("Discard the top (card|#{NUM} cards) of your opponent's deck\\.") { |m| { 'op' => 'mill_opponent', 'count' => m[2] ? m[2].to_i : 1 } },
      rule("If your opponent's Active Pokémon has exactly #{NUM} damage counters on it, that Pokémon is Knocked Out\\.") { |m| { 'op' => 'knock_out_if_counters', 'counters' => m[1].to_i } },

      # --- effects that last into the next turn
      rule("During your opponent's next turn, this Pokémon takes #{NUM} less damage from attacks \\(after applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'mark', 'target' => 'self', 'kind' => 'reduce_incoming', 'amount' => m[1].to_i, 'turns' => 1 } },
      rule("During your opponent's next turn, attacks used by the Defending Pokémon do #{NUM} less damage \\(before applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'mark', 'target' => 'defender', 'kind' => 'reduce_outgoing', 'amount' => m[1].to_i, 'turns' => 1 } },
      rule("During your opponent's next turn, the Defending Pokémon can't retreat\\.") { |_| { 'op' => 'mark', 'target' => 'defender', 'kind' => 'no_retreat', 'turns' => 1 } },
      rule("During your opponent's next turn, prevent all damage done to this Pokémon by attacks from Basic Pokémon\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'protect_from_basic', 'turns' => 1 } },
      rule("During your opponent's next turn, prevent all damage from and effects of attacks done to this Pokémon\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'protect_all', 'turns' => 1 } },
      rule("Flip a coin\\. If heads, during your opponent's next turn, prevent all damage from and effects of attacks done to this Pokémon\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'protect_all', 'turns' => 1, 'if' => 'heads' } },
      rule("Flip a coin\\. If heads, during your opponent's next turn, prevent all damage done to this Pokémon by attacks\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'protect_damage', 'turns' => 1, 'if' => 'heads' } },
      rule("During your next turn, this Pokémon can't use attacks\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'no_attack', 'turns' => 2 } },
      rule("Flip a coin\\. If tails, during your next turn, this Pokémon can't use attacks\\.") { |_| { 'op' => 'mark', 'target' => 'self', 'kind' => 'no_attack', 'turns' => 2, 'if' => 'tails' } },
      rule("During your next turn, this Pokémon can't use ([^.]+?)\\.") { |m| { 'op' => 'mark', 'target' => 'self', 'kind' => 'no_attack', 'name' => m[1], 'turns' => 2 } }
    ].freeze

    # --- Abilities
    ABILITY_PREFIXES = [
      ["Once during your turn, if this Pokémon is in the Active Spot, you may use this Ability\\.", 'activated', ->(_) { { 'active' => true } }],
      ["Once during your turn, if this Pokémon has any \\{([A-Z])\\} Energy attached, you may use this Ability\\.", 'activated', ->(m) { { 'energy_type' => TYPE_CODES[m[1]] } }],
      ['Once during your turn, when you play this Pokémon from your hand to evolve 1 of your Pokémon, you may use this Ability\.', 'on_evolve', ->(_) { {} }],
      ['Once during your turn, you may use this Ability\.', 'activated', ->(_) { {} }]
    ].freeze

    # What an Ability may do when used (on top of the attack operations that make sense there).
    ABILITY_RULES = [
      rule("Draw (a|#{NUM}) cards?\\. You can't use more than 1 [^.]+? Ability each turn\\.") { |m| { 'op' => 'draw', 'count' => count(m[2] || m[1]) } },
      rule("Heal #{NUM} damage from 1 of your Pokémon\\.") { |m| { 'op' => 'heal', 'amount' => m[1].to_i } },
      rule("Make your opponent's Active Pokémon #{CONDITION}\\.") { |m| { 'op' => 'inflict', 'condition' => condition(m[1]) } },
      rule("Flip a coin\\. If heads, discard an Energy from your opponent's Active Pokémon\\.") { |_| { 'op' => 'discard_target_energy', 'count' => 1, 'if' => 'heads' } },
      rule("Discard the top (card|#{NUM} cards) of your opponent's deck\\.") { |m| { 'op' => 'mill_opponent', 'count' => m[2] ? m[2].to_i : 1 } },
      rule("Draw (a|#{NUM}) cards?\\.") { |m| { 'op' => 'draw', 'count' => count(m[2] || m[1]) } }
    ].freeze

    # Abilities that are always on.
    PASSIVE_RULES = [
      rule("This Pokémon takes #{NUM} less damage from attacks \\(after applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'passive', 'kind' => 'reduce_incoming', 'amount' => m[1].to_i } },
      rule("This Pokémon takes #{NUM} less damage from attacks from your opponent's \\{([A-Z])\\} or \\{([A-Z])\\} Pokémon \\(after applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'passive', 'kind' => 'reduce_incoming', 'amount' => m[1].to_i, 'types' => [type_of(m[2]), type_of(m[3])] } },
      rule("Attacks used by your \\{([A-Z])\\} Pokémon do #{NUM} more damage to your opponent's Active Pokémon \\(before applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'passive', 'kind' => 'plus_damage', 'type' => type_of(m[1]), 'amount' => m[2].to_i } },
      rule("Prevent all effects of attacks used by your opponent's Pokémon done to this Pokémon\\. \\(Damage is not an effect\\.\\)") { |_| { 'op' => 'passive', 'kind' => 'protect_effects' } },
      rule("As long as this Pokémon is in the Active Spot, attacks used by your opponent's Active Pokémon do #{NUM} less damage \\(before applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'passive', 'kind' => 'reduce_opponent_damage', 'amount' => m[1].to_i } },
      rule('If this Pokémon has no Energy attached, it has no Retreat Cost\.') { |_| { 'op' => 'passive', 'kind' => 'free_retreat_without_energy' } }
    ].freeze
  end
end
