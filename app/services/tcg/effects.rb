module Tcg
  # Runs the operations that Tcg::EffectParser made of an attack (see there). Mixed into Engine.
  #
  # An attack goes: operations that change the damage (coins, bonuses, "does nothing"), the damage
  # itself with Weakness, Resistance and what lasts from earlier turns, then the other operations
  # (Special Conditions, healing, recoil, drawing ...).
  module Effects
    DAMAGE_OPS = %w[flip_each flip_until_tails flip_bonus flip_both_bonus flip_or_nothing plus_per_energy
                    per_energy_in_play plus_per_target_energy per_target_counter per_prize_taken per_own_pokemon
                    plus_if_self_damaged plus_if_target_damaged plus_if_target_condition plus_if_target_ex
                    plus_if_moved_up plus_if_own_prizes plus_if_opponent_prizes_at_most ignore].freeze
    # What a protected Pokémon is not touched by.
    TARGETING_OPS = %w[inflict knock_out_if_counters switch_opponent].freeze

    private

    # ---------------------------------------------------------------- what lasts into later turns

    def marks(slot)
      slot['marks'] ||= []
    end

    def add_mark(slot, kind, turns, extra = {})
      marks(slot).reject! { |mark| mark['until'] < turn_number }
      marks(slot) << { 'kind' => kind, 'until' => turn_number + turns }.merge(extra)
    end

    # The marks of one kind that are still in force.
    def marks_of(slot, kind)
      marks(slot).select { |mark| mark['kind'] == kind && mark['until'] >= turn_number }
    end

    # ---------------------------------------------------------------- running an attack

    def attack_ops(attack)
      Array(attack['effects'])
    end

    # Plays an attack of +seat+ against the other Active Pokémon, up to Knock Outs.
    # Returns the switch the attack asks for, if any (see do_attack).
    def resolve_attack(seat, attack)
      attacker = active(seat)
      target = active(opponent_of(seat))
      ops = attack_ops(attack)

      damage, ignore = attack_damage(seat, attack, attacker, target, ops)
      return nil if damage.nil? # "this attack does nothing"

      blocked = effects_prevented?(target, top_card(attacker))
      deal_attack_damage(seat, attacker, target, damage, ignore) if attack['damage'].to_i.positive? || damage.positive?
      say(seat, "#{top_card(target).name} is protected from the attack's effects.") if blocked && ops.any? { |op| TARGETING_OPS.include?(op['op']) }

      switches = []
      ops.each do |op|
        next if DAMAGE_OPS.include?(op['op'])
        next if blocked && (TARGETING_OPS.include?(op['op']) || (op['op'] == 'mark' && op['target'] == 'defender'))

        run_op(seat, op, attacker, target, switches)
      end
      switches.first
    end

    # The damage before it is applied (after the coins and bonuses), and what it ignores.
    # nil when the attack does nothing.
    def attack_damage(seat, attack, attacker, target, ops)
      damage = attack['damage'].to_i
      ignore = []
      ops.each do |op|
        case op['op']
        when 'flip_each' then damage = op['per'] * Array.new(op['coins']) { flip(seat) }.count(true)
        when 'flip_until_tails'
          heads = 0
          heads += 1 while flip(seat)
          damage = op['plus'] ? damage + op['per'] * heads : op['per'] * heads
        when 'flip_bonus' then damage += op['bonus'] if flip(seat)
        when 'flip_both_bonus' then damage += op['bonus'] if [flip(seat), flip(seat)].all?
        when 'flip_or_nothing'
          unless flip(seat)
            say(seat, 'The attack did nothing.')
            return nil
          end
        when 'plus_per_energy' then damage += op['per'] * energy_count(attacker, op['type'])
        when 'per_energy_in_play' then damage = op['per'] * slots(seat).sum { |slot| energy_count(slot, op['type']) }
        when 'plus_per_target_energy' then damage += op['per'] * target['energy'].size
        when 'per_target_counter' then damage = op['per'] * (target['damage'] / 10)
        when 'per_prize_taken' then damage = op['per'] * (Engine::PRIZE_CARDS - player(seat)['prizes'].size)
        when 'per_own_pokemon' then damage = op['per'] * slots(seat).size
        when 'plus_if_self_damaged' then damage += op['bonus'] if attacker['damage'].positive?
        when 'plus_if_target_damaged' then damage += op['bonus'] if target['damage'].positive?
        when 'plus_if_target_condition' then damage += op['bonus'] if condition?(target, op['condition'])
        when 'plus_if_target_ex' then damage += op['bonus'] if top_card(target).prize_value >= 2
        when 'plus_if_own_prizes' then damage += op['bonus'] if player(seat)['prizes'].size == op['prizes']
        when 'plus_if_opponent_prizes_at_most' then damage += op['bonus'] if player(opponent_of(seat))['prizes'].size <= op['prizes']
        when 'plus_if_moved_up' then damage += op['bonus'] if attacker['moved_up'] == turn_number
        when 'ignore' then ignore << op['what']
        end
      end
      [damage, ignore]
    end

    def energy_count(slot, type)
      slot['energy'].count { |uid| type.nil? || card(uid).type == type }
    end

    # Whether a Pokémon can't be touched by the effects (not the damage) of this attacker's attacks.
    def effects_prevented?(target, attacker_card)
      damage_and_effects_prevented?(target, attacker_card) || passive_ops(target, 'protect_effects').any?
    end

    def damage_and_effects_prevented?(target, attacker_card)
      marks_of(target, 'protect_all').any? || (attacker_card.prize_value >= 2 && marks_of(target, 'protect_from_ex').any?)
    end

    def deal_attack_damage(seat, attacker, target, damage, ignore)
      attacker_card = top_card(attacker)
      target_card = top_card(target)
      defender_seat = opponent_of(seat)

      if damage_and_effects_prevented?(target, attacker_card) || marks_of(target, 'protect_damage').any? ||
         (attacker_card.basic_pokemon? && marks_of(target, 'protect_from_basic').any?)
        say(seat, "#{target_card.name} is protected from the damage.")
        return
      end

      unless ignore.include?('effects')
        damage -= marks_of(attacker, 'reduce_outgoing').sum { |mark| mark['amount'] }
        damage -= passive_ops(active(defender_seat), 'reduce_opponent_damage').sum { |op| op['amount'] }
        damage = [damage, 0].max
      end
      if damage.positive?
        damage += marks_of(player(seat), 'plus_damage').select { |mark| attacker_card.energy_types.include?(mark['type']) }.sum { |mark| mark['amount'] }
        damage += own_passive_ops(seat, 'plus_damage').select { |op| attacker_card.energy_types.include?(op['type']) }.sum { |op| op['amount'] }
        damage = matchup(attacker_card, target_card, damage, ignore)
        unless ignore.include?('effects')
          damage -= marks_of(target, 'reduce_incoming').sum { |mark| mark['amount'] }
          damage -= marks_of(player(defender_seat), 'reduce_incoming').select { |mark| target_card.energy_types.include?(mark['type']) }.sum { |mark| mark['amount'] }
          damage -= tool_ops(target, 'reduce_from_ability').sum { |op| op['amount'] } if attacker_card.abilities.any?
          damage -= passive_ops(target, 'reduce_incoming').select { |op| op['types'].nil? || (op['types'] & attacker_card.energy_types).any? }.sum { |op| op['amount'] }
        end
      end
      damage = [damage, 0].max

      target['damage'] += damage
      say(seat, "#{target_card.name} took #{damage} damage.") if damage.positive?
      retaliate(attacker, target, defender_seat) if damage.positive? && target.equal?(active(defender_seat))
    end

    # A Pokémon Tool that hits back at the attacker, even when its Pokémon was Knocked Out.
    def retaliate(attacker, target, defender_seat)
      tool_ops(target, 'retaliate').each do |op|
        next unless top_card(target).energy_types.include?(op['type'])

        attacker['damage'] += op['amount']
        say(defender_seat, "#{top_card(attacker).name} took #{op['amount']} damage from #{card(target['tool']).name}.")
      end
    end

    def matchup(attacker_card, target_card, damage, ignore)
      return damage if ignore.include?('matchup')

      type = attacker_card.type
      damage *= (target_card.weakness_multiplier || 2) if target_card.weakness_type && target_card.weakness_type == type
      if target_card.resistance_type && target_card.resistance_type == type && !ignore.include?('resistance')
        damage -= target_card.resistance_amount.to_i
      end
      [damage, 0].max
    end

    def gate_open?(seat, op)
      return true unless op['if']

      flip(seat) == (op['if'] == 'heads')
    end

    def run_op(seat, op, attacker, target, switches)
      return unless gate_open?(seat, op)

      name = top_card(attacker).name
      case op['op']
      when 'inflict'
        inflict(target, op['condition']) if hp_left(target).positive?
      when 'heal_self'
        healed = [op['amount'], attacker['damage']].min
        attacker['damage'] -= healed
        say(seat, "#{name} healed #{healed} damage.") if healed.positive?
      when 'recoil'
        attacker['damage'] += op['amount']
        say(seat, "#{name} hurt itself for #{op['amount']} damage.")
      when 'discard_self_energy'
        gone = op['count'] == 'all' ? attacker['energy'].dup : attacker['energy'].first(op['count'])
        gone.each { |uid| attacker['energy'].delete(uid) }
        player(seat)['discard'].concat(gone)
        say(seat, "#{name} discarded #{gone.size} Energy.") if gone.any?
      when 'draw'
        draw(seat, op['count'])
        say(seat, "Player #{seat + 1} drew #{op['count']} #{op['count'] == 1 ? 'card' : 'cards'}.")
      when 'draw_until'
        draw(seat, [op['size'] - player(seat)['hand'].size, 0].max)
        say(seat, "Player #{seat + 1} drew until they had #{op['size']} cards.")
      when 'mill_opponent'
        milled = player(opponent_of(seat))['deck'].shift(op['count'])
        player(opponent_of(seat))['discard'].concat(milled)
        say(seat, "Player #{seat + 1} discarded the top #{milled.size} #{milled.size == 1 ? 'card' : 'cards'} of Player #{opponent_of(seat) + 1}'s deck.")
      when 'knock_out_if_counters'
        target['damage'] = top_card(target).hp if target['damage'] == op['counters'] * 10
      when 'mark'
        slot = op['target'] == 'self' ? attacker : target
        extra = op.slice('amount', 'name')
        add_mark(slot, op['kind'], op['turns'], extra)
      when 'switch_self'
        switches << { 'chooser' => seat, 'side' => seat, 'optional' => op['optional'] == true }
      when 'switch_opponent'
        switches << { 'chooser' => opponent_of(seat), 'side' => opponent_of(seat), 'optional' => false }
      when 'search'
        switches << { 'search' => op }
      end
    end
  end
end
