module Tcg
  # The patterns Tcg::EffectParser reads Trainer cards with. A card whose text isn't covered by
  # one of them (or that needs the opponent to answer a question) stays out of play.
  module TrainerRules
    SEARCH_TEXT = 'Search your deck for (a|an|up to (\d+)) ([^,.]+?)(?:, reveal (?:it|them),)? ' \
                  'and put (?:it|them) (into your hand|onto your Bench)\. Then, shuffle your deck\.'.freeze

    def self.rule(pattern, &build)
      Tcg::EffectParser.rule(pattern, &build)
    end

    NUM = Tcg::EffectParser::NUM
    TYPE = '\{([GRWLPFDMNC])\}'.freeze

    def self.type_of(code)
      Tcg::EffectParser.type_of(code)
    end

    RULES = [
      # --- conditions of use
      rule("You can use this card only if your opponent has #{NUM} or fewer Prize cards remaining\\.") { |m| { 'op' => 'require_opponent_prizes_at_most', 'count' => m[1].to_i } },
      rule("You can use this card only if you discard #{NUM} other cards from your hand\\.") { |m| { 'op' => 'discard_from_hand', 'count' => m[1].to_i } },
      rule("You can't use this card during your first turn\\.") { |_| { 'op' => 'not_on_first_turn' } },

      # --- searching the deck
      rule('Search your deck for a Basic Pokémon, a Stage 1 Pokémon, and a Stage 2 Pokémon, reveal them, and put them into your hand\. Then, shuffle your deck\.') do |_|
        { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'pokemon', 'subtype' => 'basic' },
                                                          { 'supertype' => 'pokemon', 'subtype' => 'stage1' },
                                                          { 'supertype' => 'pokemon', 'subtype' => 'stage2' }] }
      end,
      rule(SEARCH_TEXT) do |m|
        filter = Tcg::EffectParser.search_filters(m[3])
        next nil unless filter

        count = m[2] ? m[2].to_i : 1
        { 'op' => 'search', 'filters' => [filter] * count, 'to' => m[4] == 'onto your Bench' ? 'bench' : 'hand' }
      end,
      rule("Look at the top #{NUM} cards of your deck and put a #{TYPE} Pokémon you find there onto your Bench\\. Shuffle the other cards and put them on the bottom of your deck\\.") do |m|
        { 'op' => 'search', 'top' => m[1].to_i, 'to' => 'bench', 'rest' => 'bottom',
          'filters' => [{ 'supertype' => 'pokemon', 'type' => type_of(m[2]) }] }
      end,
      rule("Shuffle your hand into your deck\\. Then, draw #{NUM} cards\\. If you have exactly #{NUM} Prize cards remaining, draw #{NUM} cards instead\\.") do |m|
        { 'op' => 'shuffle_hand_draw', 'count' => m[1].to_i, 'if_prizes' => m[2].to_i, 'else_count' => m[3].to_i }
      end,

      # --- moving Pokémon and Energy around
      rule("Switch in 1 of your opponent's Benched Pokémon to the Active Spot\\.") { |_| { 'op' => 'gust' } },
      rule("Switch your Active Pokémon with 1 of your Benched Pokémon\\.") { |_| { 'op' => 'switch_own' } },
      rule("Switch out your opponent's Active Pokémon to the Bench\\. \\(Your opponent chooses the new Active Pokémon\\.\\)") { |_| { 'op' => 'switch_opponent' } },
      rule('Move a Basic Energy from 1 of your Pokémon to another of your Pokémon\.') { |_| { 'op' => 'move_energy' } },
      rule('Put a Pokémon or a Basic Energy card from your discard pile into your hand\.') do |_|
        { 'op' => 'recover', 'filter' => { 'any' => [{ 'supertype' => 'pokemon' }, { 'supertype' => 'energy', 'basic_energy' => true }] } }
      end,
      rule("Attach a Basic #{TYPE} Energy card from your discard pile to 1 of your Benched #{TYPE} Pokémon\\.") do |m|
        { 'op' => 'attach_from_discard', 'type' => type_of(m[1]) }
      end,
      rule('Choose 1 of your Basic Pokémon in play\. If you have a Stage 2 card in your hand that evolves from that Pokémon, put that card onto the Basic Pokémon to evolve it, skipping the Stage 1\. You can\'t use this card during your first turn or on a Basic Pokémon that was put into play this turn\.') { |_| { 'op' => 'rare_candy' } },

      # --- healing
      rule("Heal #{NUM} damage from 1 of your Pokémon, and it recovers from all Special Conditions\\.") { |m| { 'op' => 'heal', 'amount' => m[1].to_i, 'cure' => true } },
      rule("Heal #{NUM} damage from your Active Pokémon that has 3 or more Energy attached\\.") { |m| { 'op' => 'heal', 'amount' => m[1].to_i, 'active_only' => true, 'min_energy' => 3 } },
      rule('Heal all damage from 1 of your Mega Evolution Pokémon ex\. If you healed any damage in this way, put all Energy attached to that Pokémon into your hand\.') { |_| { 'op' => 'heal', 'amount' => 'all', 'mega_only' => true, 'return_energy' => true } },

      # --- lasting effects
      rule("During this turn, attacks used by your #{TYPE} Pokémon do #{NUM} more damage to your opponent's Active Pokémon \\(before applying Weakness and Resistance\\)\\.") do |m|
        { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => type_of(m[1]), 'amount' => m[2].to_i, 'turns' => 0 }
      end,
      rule("During your opponent's next turn, all of your #{TYPE} Pokémon take #{NUM} less damage from attacks from your opponent's Pokémon \\(after applying Weakness and Resistance\\)\\. \\(This includes new Pokémon that come into play\\.\\)") do |m|
        { 'op' => 'player_mark', 'kind' => 'reduce_incoming', 'type' => type_of(m[1]), 'amount' => m[2].to_i, 'turns' => 1 }
      end,
      rule("Choose 1 of your Pokémon in play\\. During your opponent's next turn, prevent all damage from and effects of attacks done to that Pokémon by your opponent's Pokémon ex\\.") { |_| { 'op' => 'protect_own', 'from' => 'ex' } },

      # --- Pokémon Tools
      rule('The Retreat Cost of the Pokémon this card is attached to is \{C\}\{C\} less\.') { |_| { 'op' => 'tool', 'kind' => 'retreat_less', 'amount' => 2 } },
      rule("If the #{TYPE} Pokémon this card is attached to is in the Active Spot and is damaged by an attack from your opponent's Pokémon \\(even if this Pokémon is Knocked Out\\), place #{NUM} damage counters on the Attacking Pokémon\\.") do |m|
        { 'op' => 'tool', 'kind' => 'retaliate', 'type' => type_of(m[1]), 'amount' => m[2].to_i * 10 }
      end,
      rule("The Pokémon this card is attached to takes #{NUM} less damage from attacks from your opponent's Pokémon that have an Ability \\(after applying Weakness and Resistance\\)\\.") { |m| { 'op' => 'tool', 'kind' => 'reduce_from_ability', 'amount' => m[1].to_i } },

      # --- Stadiums
      rule("Each player's #{TYPE} Pokémon can evolve into #{TYPE} Pokémon during the turn they play those Pokémon, except during their first turn\\.") { |m| { 'op' => 'stadium', 'kind' => 'evolve_at_once', 'type' => type_of(m[1]) } },
      rule("Whenever any player puts a Basic non-#{TYPE} Pokémon onto their Bench during their turn, place #{NUM} damage counters on that Pokémon\\.") { |m| { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => type_of(m[1]), 'amount' => m[2].to_i * 10 } }
    ].freeze
  end
end
