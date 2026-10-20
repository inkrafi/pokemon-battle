module Tcg
  # Abilities of Pokémon in play. Mixed into Engine.
  #
  # A card keeps each Ability as { 'name', 'trigger', 'needs', 'effects' } (see EffectParser.ability).
  # Passive ones are always on and are asked about by the damage code; ones used "once during your
  # turn" are the "ability" action; ones that happen when a Pokémon evolves run by themselves.
  module Abilities
    private

    def supported_abilities(slot)
      top_card(slot).abilities.select { |ability| ability['supported'] }
    end

    # The operations of a kind from the passive Abilities of one Pokémon.
    def passive_ops(slot, kind)
      return [] unless slot

      supported_abilities(slot).select { |ability| ability['trigger'] == 'passive' }
                               .flat_map { |ability| ability['effects'] }.select { |op| op['kind'] == kind }
    end

    # The same over all the Pokémon of a player.
    def own_passive_ops(seat, kind)
      slots(seat).flat_map { |slot| passive_ops(slot, kind) }
    end

    # ---------------------------------------------------------------- using an Ability

    def ability_of(slot, index)
      supported_abilities(slot)[index.to_i] if index.is_a?(Integer) && index >= 0
    end

    def check_ability(seat, action)
      slot = slot_at(seat, action['slot'])
      return 'Choose one of your Pokémon.' unless slot

      ability = ability_of(slot, action['index'])
      return "#{top_card(slot).name} has no such Ability." unless ability && ability['trigger'] == 'activated'
      return "You already used #{ability['name']} this turn." if player(seat)['flags']['abilities'].include?(ability['name'])

      needs = ability['needs']
      return "#{ability['name']} can only be used by a Pokémon in the Active Spot." if needs['active'] && !active(seat).equal?(slot)
      return "#{ability['name']} needs #{needs['energy_type']} Energy on the Pokémon." if needs['energy_type'] && energy_count(slot, needs['energy_type']).zero?

      ability_fields(seat, ability).each do |field|
        values = field['options'].map(&:first)
        return "Nothing to choose for: #{field['label'].downcase}." if values.empty?
        return "Choose a value for: #{field['label'].downcase}." unless values.include?(action[field['field']])
      end
      nil
    end

    def ability_fields(seat, ability)
      ability['effects'].flat_map { |op| op['op'] == 'heal' ? op_fields(op, seat, nil) : [] }
    end
    public :ability_fields

    def do_ability(seat, action)
      slot = slot_at(seat, action['slot'])
      ability = ability_of(slot, action['index'])
      player(seat)['flags']['abilities'] << ability['name']
      say(seat, "#{top_card(slot).name} used #{ability['name']}.")
      ability['effects'].each { |op| run_ability_op(seat, slot, op, action) }
      sweep_knockouts(by: seat)
    end

    def run_ability_op(seat, slot, op, action)
      other = opponent_of(seat)
      return unless gate_open?(seat, op)

      case op['op']
      when 'draw' then run_op(seat, op, slot, slot, [])
      when 'mill_opponent' then run_op(seat, op, slot, active(other), [])
      when 'heal' then run_trainer_op(seat, nil, op, action)
      when 'inflict' then inflict(active(other), op['condition']) if active(other)
      when 'discard_target_energy'
        target = active(other)
        gone = target && target['energy'].shift(op['count'])
        return unless gone&.any?

        player(other)['discard'].concat(gone)
        say(seat, "#{card(gone.first).name} was discarded from #{top_card(target).name}.")
      end
    end

    # Abilities that happen when a Pokémon evolves. The player has no choices: a heal goes to the
    # first damaged Pokémon.
    def trigger_on_evolve(seat, slot)
      supported_abilities(slot).select { |ability| ability['trigger'] == 'on_evolve' }.each do |ability|
        say(seat, "#{top_card(slot).name}'s #{ability['name']} was used.")
        ability['effects'].each do |op|
          if op['op'] == 'heal'
            target = healable(op, seat).first&.first
            run_ability_op(seat, slot, op, { 'target' => target }) if target
          else
            run_ability_op(seat, slot, op, {})
          end
        end
      end
      sweep_knockouts(by: seat)
    end

    def ability_candidates(seat)
      own_targets(seat).flat_map do |target, slot|
        supported_abilities(slot).each_with_index.flat_map do |ability, index|
          next [] unless ability['trigger'] == 'activated'

          fields = ability_fields(seat, ability)
          base = { 'type' => 'ability', 'slot' => target, 'index' => index }
          next [base] if fields.empty?

          fields.map { |field| field['options'].map { |value, _| [field['field'], value] }.first(6) }
                .then { |combos| combos.first.product(*combos.drop(1)) }.map { |pairs| base.merge(pairs.to_h) }
        end
      end
    end
  end
end
