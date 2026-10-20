module Tcg
  # Whether attached Energy can pay for an attack or a retreat.
  # A colored symbol needs Energy of that type, Colorless can be paid with anything.
  module EnergyCost
    COLORLESS = 'Colorless'.freeze

    # +provided+: the types the attached Energy gives, one entry per Energy card.
    # +cost+: the symbols on the attack, for example ["Fire", "Colorless"].
    def self.payable?(provided, cost)
      remaining = provided.tally
      cost.each do |symbol|
        next if symbol == COLORLESS
        return false unless remaining[symbol].to_i.positive?

        remaining[symbol] -= 1
      end

      remaining.values.sum >= cost.count(COLORLESS)
    end
  end
end
