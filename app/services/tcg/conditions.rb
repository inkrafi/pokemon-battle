module Tcg
  # Special Conditions and the Pokémon Checkup between turns. Mixed into Engine.
  #
  # Poisoned and Burned can be combined with each other and with one of Asleep, Confused or
  # Paralyzed. A new one of those three replaces the one a Pokémon already has. Moving to the
  # Bench or evolving cures everything.
  module Conditions
    ALL = %w[poisoned burned asleep confused paralyzed].freeze
    ROTATION = %w[asleep confused paralyzed].freeze
    CHECKUP_DAMAGE = 10
    CONFUSION_DAMAGE = 30

    private

    def conditions(slot)
      slot['conditions'] ||= []
    end

    def condition?(slot, name)
      conditions(slot).include?(name)
    end

    def inflict(slot, name)
      list = conditions(slot)
      list.reject! { |other| ROTATION.include?(other) } if ROTATION.include?(name)
      list << name unless list.include?(name)
      say(nil, "#{top_card(slot).name} is now #{name.capitalize}.")
    end

    def cure_all(slot)
      conditions(slot).clear
    end

    # Between turns, after the turn of +ended+: each Active Pokémon is checked, the one of the
    # player whose turn just ended included. Paralysis only wears off after its owner's own turn.
    def run_checkup(ended)
      say(nil, 'Pokémon Checkup.')
      seats = [ended, opponent_of(ended)]
      seats.each { |seat| checkup_damage(seat) }
      seats.each { |seat| checkup_flips(seat, ended) }
      sweep_knockouts(by: ended)
    end

    def checkup_damage(seat)
      slot = active(seat)
      return unless slot

      %w[poisoned burned].each do |name|
        next unless condition?(slot, name)

        slot['damage'] += CHECKUP_DAMAGE
        say(nil, "#{top_card(slot).name} took #{CHECKUP_DAMAGE} damage from being #{name.capitalize}.")
      end
    end

    def checkup_flips(seat, ended)
      slot = active(seat)
      return unless slot

      if condition?(slot, 'asleep') && flip(seat, "to wake #{top_card(slot).name}")
        conditions(slot).delete('asleep')
        say(nil, "#{top_card(slot).name} woke up.")
      end
      if condition?(slot, 'burned') && flip(seat, "to heal #{top_card(slot).name}'s Burn")
        conditions(slot).delete('burned')
        say(nil, "#{top_card(slot).name} is no longer Burned.")
      end
      if condition?(slot, 'paralyzed') && seat == ended
        conditions(slot).delete('paralyzed')
        say(nil, "#{top_card(slot).name} is no longer Paralyzed.")
      end
    end

    # Heads is true. The result goes into the log.
    def flip(seat, purpose = nil)
      heads = @rng.rand(2) == 1
      say(seat, "Player #{seat + 1} flipped a coin#{" #{purpose}" if purpose}: #{heads ? 'heads' : 'tails'}.")
      heads
    end
  end
end
