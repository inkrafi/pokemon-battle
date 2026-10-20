module Tcg
  # Which cards a search or a choice may pick: a small hash, for example
  #   { 'supertype' => 'pokemon', 'subtype' => 'basic', 'max_hp' => 70 }
  #   { 'any' => [filter, filter] }
  module CardFilter
    module_function

    def match?(card, filter)
      return filter['any'].any? { |option| match?(card, option) } if filter['any']

      filter.all? do |key, value|
        case key
        when 'supertype' then card.supertype == value
        when 'subtype' then card.subtype == value
        when 'basic_energy' then card.basic_energy? == value
        when 'type' then card.energy_types.include?(value)
        when 'max_hp' then card.hp.to_i <= value
        when 'mega' then (card.prize_value >= 3) == value
        else raise ArgumentError, "Unknown filter #{key}"
        end
      end
    end
  end
end
