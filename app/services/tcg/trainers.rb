module Tcg
  # Playing Trainer cards: Items, Supporters, Stadiums and Pokémon Tools. Mixed into Engine.
  #
  # A Trainer is a list of operations (see Tcg::TrainerRules). The choices it needs are named
  # fields of the "play" action: play_fields lists them with every value that is allowed, which
  # is what the page builds its form from and what the computer picks from.
  #
  #   { 'type' => 'play', 'card' => 12, 'target' => 'bench-0' }
  module Trainers
    SUBTYPES = %w[item supporter stadium tool].freeze
    TOOL_OPS = %w[tool].freeze

    private

    def trainer_ops(card)
      Array(card.effects)
    end

    # ---------------------------------------------------------------- what a card needs

    # The choices for playing a card now: [{ 'field', 'label', 'options' => [[value, text]], 'count' }].
    # +count+ is set when a list of that many values is wanted.
    def play_fields(seat, uid)
      trainer_ops(card(uid)).flat_map { |op| op_fields(op, seat, uid) }
    end
    public :play_fields

    def op_fields(op, seat, uid)
      p = player(seat)
      case op['op']
      when 'discard_from_hand'
        [{ 'field' => 'discard', 'label' => 'Cards to discard', 'count' => op['count'],
           'options' => (p['hand'] - [uid]).map { |other| [other, card(other).name] } }]
      when 'gust'
        [{ 'field' => 'opp', 'label' => "Opponent's Benched Pokémon",
           'options' => bench(opponent_of(seat)).each_with_index.map { |slot, index| [index, top_card(slot).name] } }]
      when 'switch_own'
        [{ 'field' => 'to', 'label' => 'Switch with', 'options' => p['bench'].each_with_index.map { |slot, index| [index, "#{top_card(slot).name} (Bench #{index + 1})"] } }]
      when 'move_energy'
        energies = own_targets(seat).flat_map do |target, slot|
          slot['energy'].select { |energy| card(energy).basic_energy? }.map { |energy| [energy, "#{card(energy).name} on #{slot_label(seat, target)}"] }
        end
        [{ 'field' => 'energy', 'label' => 'Energy to move', 'options' => energies },
         { 'field' => 'to_target', 'label' => 'Move it to', 'options' => own_targets(seat).map { |target, _| [target, slot_label(seat, target)] } }]
      when 'recover'
        [{ 'field' => 'pick', 'label' => 'Card to take back',
           'options' => unique_by_card(p['discard']).select { |other| CardFilter.match?(card(other), op['filter']) }.map { |other| [other, card(other).name] } }]
      when 'attach_from_discard'
        [{ 'field' => 'pick', 'label' => 'Energy to attach',
           'options' => unique_by_card(p['discard']).select { |other| card(other).basic_energy? && card(other).type == op['type'] }.map { |other| [other, card(other).name] } },
         { 'field' => 'target', 'label' => 'Benched Pokémon',
           'options' => p['bench'].each_with_index.select { |slot, _| top_card(slot).energy_types.include?(op['type']) }.map { |slot, index| ["bench-#{index}", slot_label(seat, "bench-#{index}")] } }]
      when 'heal'
        [{ 'field' => 'target', 'label' => 'Pokémon to heal', 'options' => healable(op, seat).map { |target, _| [target, slot_label(seat, target)] } }]
      when 'rare_candy'
        pairs = candy_pairs(seat)
        [{ 'field' => 'target', 'label' => 'Basic Pokémon', 'options' => pairs.map(&:first).uniq.map { |target| [target, slot_label(seat, target)] } },
         { 'field' => 'with', 'label' => 'Stage 2 card', 'options' => pairs.map(&:last).uniq.map { |stage| [stage, card(stage).name] } }]
      when 'protect_own'
        [{ 'field' => 'target', 'label' => 'Pokémon to protect', 'options' => own_targets(seat).map { |target, _| [target, slot_label(seat, target)] } }]
      when 'tool'
        [{ 'field' => 'target', 'label' => 'Attach to',
           'options' => own_targets(seat).select { |_, slot| slot['tool'].nil? }.map { |target, _| [target, slot_label(seat, target)] } }]
      else
        []
      end
    end

    # [['active', slot], ['bench-0', slot] ...]
    def own_targets(seat)
      list = []
      list << ['active', active(seat)] if active(seat)
      bench(seat).each_with_index { |slot, index| list << ["bench-#{index}", slot] }
      list
    end

    def slot_label(seat, target)
      slot = slot_at(seat, target)
      place = target == 'active' ? 'Active' : "Bench #{target.split('-').last.to_i + 1}"
      "#{top_card(slot).name} (#{place})"
    end

    def healable(op, seat)
      own_targets(seat).select do |target, slot|
        slot['damage'].positive? &&
          (!op['active_only'] || target == 'active') &&
          (!op['min_energy'] || slot['energy'].size >= op['min_energy']) &&
          (!op['mega_only'] || top_card(slot).prize_value >= 3)
      end
    end

    # The Basic Pokémon in play a Rare Candy could be used on, with the Stage 2 cards in hand for them.
    def candy_pairs(seat)
      p = player(seat)
      return [] if p['turns_taken'] <= 1

      stage2s = p['hand'].select { |uid| card(uid).pokemon? && card(uid).subtype == 'stage2' }
      own_targets(seat).flat_map do |target, slot|
        next [] unless top_card(slot).basic_pokemon? && slot['stack'].size == 1 && slot['since'] < turn_number

        stage2s.select { |stage| evolves_through?(card(stage), top_card(slot)) }.map { |stage| [target, stage] }
      end
    end

    # Whether +stage2+ can evolve from +basic+ via a Stage 1 card.
    def evolves_through?(stage2, basic)
      Card.where(name: stage2.evolves_from, subtype: 'stage1', evolves_from: basic.name).exists?
    end

    # ---------------------------------------------------------------- checks

    def check_play(seat, action)
      p = player(seat)
      uid = action['card']
      return 'That card is not in your hand.' unless p['hand'].include?(uid)

      played = card(uid)
      return 'Only a Trainer card can be played.' unless played.trainer?

      message = subtype_error(seat, played) || requirement_error(seat, played)
      return message if message

      fields_error(seat, uid, action)
    end

    def subtype_error(seat, played)
      p = player(seat)
      case played.subtype
      when 'supporter'
        return "The player who goes first can't play a Supporter on the first turn." if turn_number == 1
        return 'You already played a Supporter this turn.' if p['flags']['supporter']
      when 'stadium'
        return 'You already played a Stadium this turn.' if p['flags']['stadium']
        return "A Stadium named #{played.name} is already in play." if stadium_card&.name == played.name
      when 'item', 'tool'
        nil
      else
        return "#{played.name} can't be played."
      end
      nil
    end

    def requirement_error(seat, played)
      trainer_ops(played).each do |op|
        case op['op']
        when 'require_opponent_prizes_at_most'
          return "You can only play #{played.name} when your opponent has #{op['count']} or fewer Prize cards left." if player(opponent_of(seat))['prizes'].size > op['count']
        when 'not_on_first_turn'
          return "You can't play #{played.name} on your first turn." if player(seat)['turns_taken'] <= 1
        when 'search'
          return 'There is no room on your Bench.' if op['to'] == 'bench' && bench(seat).size >= Engine::BENCH_SIZE
          return 'Your deck is empty.' if player(seat)['deck'].empty?
        when 'gust'
          return "Your opponent has nothing on the Bench to switch in." if bench(opponent_of(seat)).empty?
        when 'switch_opponent'
          return "Your opponent has nothing on the Bench to switch with." if bench(opponent_of(seat)).empty?
        when 'switch_own'
          return 'You have nothing on the Bench to switch with.' if bench(seat).empty? || active(seat).nil?
        end
      end
      nil
    end

    def fields_error(seat, uid, action)
      play_fields(seat, uid).each do |field|
        value = action[field['field']]
        values = field['options'].map(&:first)

        if field['count']
          list = Array(value)
          return "Choose #{field['count']} cards for: #{field['label'].downcase}." unless field['options'].size >= field['count']
          return "Choose #{field['count']} cards for: #{field['label'].downcase}." unless list.size == field['count'] && list.uniq == list && list.all? { |item| values.include?(item) }
        else
          return "Nothing to choose for: #{field['label'].downcase}." if values.empty?
          return "Choose a value for: #{field['label'].downcase}." unless values.include?(value)
        end
      end

      pair_error(seat, action, trainer_ops(card(uid)))
    end

    def pair_error(seat, action, ops)
      if ops.any? { |op| op['op'] == 'move_energy' }
        holder = own_targets(seat).find { |_, slot| slot['energy'].include?(action['energy']) }&.first
        return 'Choose a different Pokémon to move the Energy to.' if holder == action['to_target']
      end
      if ops.any? { |op| op['op'] == 'rare_candy' } && !candy_pairs(seat).include?([action['target'], action['with']])
        return "That card doesn't evolve from the chosen Pokémon."
      end
      if ops.any? { |op| op['op'] == 'heal' } && !healable(ops.find { |op| op['op'] == 'heal' }, seat).any? { |target, _| target == action['target'] }
        return 'That Pokémon has no damage to heal.'
      end

      nil
    end

    # ---------------------------------------------------------------- playing a card

    def do_play(seat, action)
      p = player(seat)
      uid = action['card']
      played = card(uid)
      p['hand'].delete(uid)
      say(seat, "Player #{seat + 1} played #{played.name}.")

      case played.subtype
      when 'supporter' then p['flags']['supporter'] = true
      when 'stadium'
        p['flags']['stadium'] = true
        replace_stadium(seat, uid)
      end

      ops = trainer_ops(played)
      p['discard'] << uid if %w[item supporter].include?(played.subtype)
      ops.each { |op| run_trainer_op(seat, uid, op, action) }
      sweep_knockouts(by: seat) # a Stadium or Tool may have left a Pokémon with no HP
    end

    def replace_stadium(seat, uid)
      if state['stadium']
        owner = state['stadium']['owner']
        player(owner)['discard'] << state['stadium']['uid']
        say(seat, "#{card(state['stadium']['uid']).name} was discarded.")
      end
      state['stadium'] = { 'uid' => uid, 'owner' => seat }
    end

    def stadium_card
      state['stadium'] && card(state['stadium']['uid'])
    end

    # Operations of the Stadium in play, of one kind.
    def stadium_ops(kind)
      return [] unless state['stadium']

      trainer_ops(stadium_card).select { |op| op['op'] == 'stadium' && op['kind'] == kind }
    end

    def tool_ops(slot, kind)
      return [] unless slot['tool']

      trainer_ops(card(slot['tool'])).select { |op| op['op'] == 'tool' && op['kind'] == kind }
    end

    def run_trainer_op(seat, uid, op, action)
      p = player(seat)
      other = opponent_of(seat)
      case op['op']
      when 'discard_from_hand'
        action['discard'].each do |gone|
          p['hand'].delete(gone)
          p['discard'] << gone
        end
        say(seat, "Player #{seat + 1} discarded #{action['discard'].size} cards from their hand.")
      when 'search'
        start_search(seat, op)
      when 'shuffle_hand_draw'
        p['deck'].concat(p['hand'])
        p['hand'] = []
        shuffle(seat)
        count = p['prizes'].size == op['if_prizes'] ? op['else_count'] : op['count']
        draw(seat, count)
        say(seat, "Player #{seat + 1} shuffled their hand into their deck and drew #{count} cards.")
      when 'gust'
        switch_active(other, action['opp'])
      when 'switch_own'
        switch_active(seat, action['to'])
      when 'switch_opponent'
        state['pending'] = { 'type' => 'switch', 'seat' => other, 'side' => other, 'optional' => false, 'stage' => 'trainer' } if bench(other).any?
      when 'move_energy'
        from = own_targets(seat).find { |_, slot| slot['energy'].include?(action['energy']) }.last
        from['energy'].delete(action['energy'])
        slot_at(seat, action['to_target'])['energy'] << action['energy']
        say(seat, "Player #{seat + 1} moved #{card(action['energy']).name} to #{top_card(slot_at(seat, action['to_target'])).name}.")
      when 'recover'
        p['discard'].delete_at(p['discard'].index(action['pick']))
        p['hand'] << action['pick']
        say(seat, "Player #{seat + 1} took #{card(action['pick']).name} back into their hand.")
      when 'attach_from_discard'
        p['discard'].delete_at(p['discard'].index(action['pick']))
        slot = slot_at(seat, action['target'])
        slot['energy'] << action['pick']
        say(seat, "Player #{seat + 1} attached #{card(action['pick']).name} to #{top_card(slot).name}.")
      when 'heal'
        heal_slot(seat, op, slot_at(seat, action['target']))
      when 'player_mark'
        add_mark(p, op['kind'], op['turns'], op.slice('type', 'amount'))
      when 'rare_candy'
        slot = slot_at(seat, action['target'])
        p['hand'].delete(action['with'])
        slot['stack'] << action['with']
        slot['since'] = turn_number
        slot['evolved'] = turn_number
        cure_all(slot)
        say(seat, "Player #{seat + 1} evolved #{card(slot['stack'].first).name} into #{card(action['with']).name} with a Rare Candy.")
        trigger_on_evolve(seat, slot)
      when 'protect_own'
        add_mark(slot_at(seat, action['target']), 'protect_from_ex', 1)
      when 'tool'
        slot = slot_at(seat, action['target'])
        slot['tool'] = uid
        say(seat, "#{card(uid).name} was attached to #{top_card(slot).name}.")
      end
    end

    def heal_slot(seat, op, slot)
      healed = op['amount'] == 'all' ? slot['damage'] : [op['amount'], slot['damage']].min
      slot['damage'] -= healed
      say(seat, "#{top_card(slot).name} healed #{healed} damage.")
      cure_all(slot) if op['cure']
      return unless op['return_energy'] && healed.positive?

      player(seat)['hand'].concat(slot['energy'])
      slot['energy'] = []
    end

    # ---------------------------------------------------------------- searching the deck

    def start_search(seat, op, after: nil)
      p = player(seat)
      filters = op['filters'].dup
      filters = filters.first([Engine::BENCH_SIZE - p['bench'].size, 0].max) if op['to'] == 'bench'
      source = op['top'] ? p['deck'].first(op['top']) : p['deck'].dup
      state['pending'] = { 'type' => 'search', 'seat' => seat, 'filters' => filters, 'to' => op['to'],
                           'top' => op['top'], 'rest' => op['rest'], 'source' => source, 'after' => after }
      finish_search(seat, []) if filters.empty?
    end

    def check_choose(seat, action)
      return 'There is nothing to choose.' unless pending && pending['type'] == 'search' && pending['seat'] == seat

      chosen = Array(action['cards'])
      return 'Choose cards from the list.' unless chosen.uniq == chosen && chosen.all? { |uid| pending['source'].include?(uid) }
      return "Those cards don't fit the search." unless search_assignment(pending['filters'], chosen)

      nil
    end

    # Whether each chosen card can be matched with its own filter.
    def search_assignment(filters, chosen)
      return true if chosen.empty?
      return false if chosen.size > filters.size

      first, *rest = chosen
      filters.each_index.any? do |index|
        CardFilter.match?(card(first), filters[index]) && search_assignment(filters.dup.tap { |list| list.delete_at(index) }, rest)
      end
    end

    def do_choose(seat, action)
      finish_search(seat, Array(action['cards']))
    end

    def finish_search(seat, chosen)
      pend = state['pending']
      state['pending'] = nil
      p = player(seat)
      names = chosen.map { |uid| card(uid).name }

      chosen.each { |uid| p['deck'].delete_at(p['deck'].index(uid)) }
      if pend['to'] == 'bench'
        chosen.each do |uid|
          slot = new_slot(uid, since: turn_number)
          p['bench'] << slot
          on_benched(seat, slot)
        end
      elsif pend['to'] == 'self'
        active(seat)['energy'].concat(chosen)
      else
        p['hand'].concat(chosen)
      end

      if pend['top']
        looked = p['deck'].shift([pend['top'] - chosen.size, p['deck'].size].min)
        p['deck'].concat(looked.shuffle(random: @rng))
      else
        shuffle(seat)
      end

      say(seat, names.any? ? "Player #{seat + 1} searched their deck and took #{names.join(', ')}." : "Player #{seat + 1} searched their deck and took nothing.")
      sweep_knockouts(by: seat)
      after_turn(pend['after']) if pend['after'] && !finished? && state['pending'].nil?
    end

    # A Basic Pokémon was put on the Bench during a turn.
    def on_benched(seat, slot)
      stadium_ops('bench_damage').each do |op|
        next if top_card(slot).energy_types.include?(op['except_type'])

        slot['damage'] += op['amount']
        say(seat, "#{top_card(slot).name} took #{op['amount']} damage from #{stadium_card.name}.")
      end
    end

    # ---------------------------------------------------------------- listing

    def trainer_candidates(seat)
      unique_by_card(player(seat)['hand']).select { |uid| card(uid).trainer? }.flat_map do |uid|
        fields = play_fields(seat, uid)
        next [{ 'type' => 'play', 'card' => uid }] if fields.empty?
        next [] if fields.any? { |field| field['options'].empty? || (field['count'] && field['options'].size < field['count']) }

        combos = fields.map do |field|
          field['count'] ? field['options'].map(&:first).first(field['count']).then { |list| [[field['field'], list]] } : field['options'].map { |value, _| [field['field'], value] }.first(8)
        end
        combos.first.product(*combos.drop(1)).first(12).map { |pairs| { 'type' => 'play', 'card' => uid }.merge(pairs.to_h) }
      end
    end

    def pending_search_candidates(seat)
      return [{ 'type' => 'concede' }] unless pending['seat'] == seat

      picks = []
      remaining = pending['filters'].dup
      pending['source'].each do |uid|
        index = remaining.index { |filter| CardFilter.match?(card(uid), filter) }
        next unless index

        remaining.delete_at(index)
        picks << uid
      end
      [{ 'type' => 'choose', 'cards' => picks }, { 'type' => 'choose', 'cards' => [] }, { 'type' => 'concede' }].uniq
    end
  end
end
