module Tcg
  # The rules of a game of the Pokemon Trading Card Game, for two players ("seats" 0 and 1).
  #
  # The whole board is a plain Hash (+state+) that can be saved as JSON and loaded again, so the
  # engine itself holds nothing between calls. Every card in the game has a number, its uid;
  # state['cards'][uid] is the id of the Card record it is a copy of. Zones hold uids.
  #
  #   engine = Tcg::Engine.start(decks: [card_ids_a, card_ids_b])
  #   engine.legal_actions(0)                       # what seat 0 may do now
  #   engine.perform(0, 'type' => 'setup', 'active' => uid, 'bench' => [])
  #
  # Rules covered: setup with mulligans, the turn (draw, Bench, one Energy, evolve, retreat,
  # attack), Weakness and Resistance, Special Conditions with the Pokémon Checkup, Knock Outs
  # and Prize cards, and the three ways to win.
  class Engine
    include Conditions
    include Effects
    include Trainers
    include Abilities

    HAND_SIZE = 7
    PRIZE_CARDS = 6
    BENCH_SIZE = 5
    LOG_LIMIT = 300
    ACTIONS = %w[setup bench attach evolve retreat attack end_turn promote switch play choose ability concede].freeze
    # The action each kind of pending choice waits for, and what the other player sees meanwhile.
    PENDING = {
      'promote' => { action: 'promote', waiting: 'Your opponent is choosing a new Active Pokémon.', prompt: 'Choose your new Active Pokémon.' },
      'switch' => { action: 'switch', waiting: 'Your opponent is choosing which Pokémon to switch in.', prompt: 'Choose which Pokémon to switch in.' },
      'search' => { action: 'choose', waiting: 'Your opponent is searching their deck.', prompt: 'Finish your search first.' }
    }.freeze

    attr_reader :state

    # Starts a game. +decks+ is one list of Card ids per seat. +first_player+ is decided by a
    # coin flip unless given. +shuffle: false+ keeps decks in the order given (for tests).
    def self.start(decks:, first_player: nil, rng: Random.new, shuffle: true, catalog: nil)
      cards = []
      players = decks.map do |card_ids|
        uids = card_ids.map { |card_id| cards << card_id; cards.size - 1 }
        { 'deck' => uids, 'hand' => [], 'discard' => [], 'prizes' => [], 'active' => nil, 'bench' => [],
          'mulligans' => 0, 'setup_done' => false, 'turns_taken' => 0,
          'flags' => { 'energy' => false, 'retreat' => false, 'supporter' => false, 'stadium' => false, 'abilities' => [] } }
      end

      state = { 'version' => 1, 'phase' => 'setup', 'cards' => cards, 'players' => players,
                'first_player' => first_player || rng.rand(2), 'current' => nil, 'turn_number' => 0,
                'pending' => nil, 'stadium' => nil, 'winner' => nil, 'win_reason' => nil, 'log' => [] }
      engine = new(state, rng: rng, shuffle: shuffle, catalog: catalog)
      engine.send(:open_game)
      engine
    end

    def initialize(state, rng: Random.new, shuffle: true, catalog: nil)
      @state = state
      @rng = rng
      @shuffle = shuffle
      @catalog = catalog
    end

    # ------------------------------------------------------------------ reading the game

    def phase = state['phase']
    def current = state['current']
    def turn_number = state['turn_number']
    def pending = state['pending']
    def winner = state['winner']
    def win_reason = state['win_reason']
    def first_player = state['first_player']
    def log = state['log']
    def finished? = phase == 'finished'

    # The seat that has to do something now: the one that must choose a new Active Pokemon, the
    # player whose turn it is, or during setup the first seat that hasn't placed its Pokemon.
    def seat_to_act
      return nil if finished?
      return pending['seat'] if pending
      return current if phase == 'play'

      state['players'].index { |player| !player['setup_done'] }
    end

    def player(seat) = state['players'].fetch(seat)
    def opponent_of(seat) = 1 - seat
    def active(seat) = player(seat)['active']
    def bench(seat) = player(seat)['bench']

    def catalog
      @catalog ||= Card.where(id: state['cards'].uniq).index_by(&:id)
    end

    def card(uid) = catalog.fetch(state['cards'].fetch(uid))

    # The card on top of a Pokemon in play: the one that is actually fighting.
    def top_card(slot) = card(slot['stack'].last)

    def slots(seat)
      [active(seat), *bench(seat)].compact
    end

    # The Pokemon a target name points at: 'active' or 'bench-2'.
    def slot_at(seat, target)
      return active(seat) if target == 'active'
      return nil unless target.to_s.match?(/\Abench-\d+\z/)

      bench(seat)[target.split('-').last.to_i]
    end

    def attached_types(slot)
      slot['energy'].map { |uid| card(uid).type }
    end

    def hp_left(slot)
      top_card(slot).hp - slot['damage']
    end

    # How many cards a seat has in all zones (a Stadium in play counts for the player who played
    # it). Always the size of its deck.
    def card_total(seat)
      p = player(seat)
      p['deck'].size + p['hand'].size + p['discard'].size + p['prizes'].size + (state['stadium'] && state['stadium']['owner'] == seat ? 1 : 0) +
        slots(seat).sum { |slot| slot['stack'].size + slot['energy'].size + (slot['tool'] ? 1 : 0) }
    end

    # ------------------------------------------------------------------ doing things

    # Everything +seat+ may do right now. For a setup, one sample per Active Pokemon is listed;
    # any valid combination is accepted by #perform.
    def legal_actions(seat)
      return [] if finished?

      candidates(seat).select { |action| error_for(seat, action).nil? }
    end

    # The reason an action isn't allowed, or nil when it is.
    def error_for(seat, action)
      action = action.deep_stringify_keys
      return 'The game is over.' if finished?
      return 'Unknown seat.' unless [0, 1].include?(seat)
      return 'Unknown action.' unless ACTIONS.include?(action['type'])
      return nil if action['type'] == 'concede'

      if phase == 'setup'
        return 'Place your Pokémon first.' unless action['type'] == 'setup'
      elsif pending
        return PENDING.fetch(pending['type'])[:waiting] unless pending['seat'] == seat
        return PENDING.fetch(pending['type'])[:prompt] unless action['type'] == PENDING.fetch(pending['type'])[:action]
      elsif seat != current
        return 'It is not your turn.'
      end

      send("check_#{action['type']}", seat, action)
    end

    def perform(seat, action)
      action = action.deep_stringify_keys
      message = error_for(seat, action)
      raise IllegalAction, message if message

      send("do_#{action['type']}", seat, action)
      self
    end

    private

    # ------------------------------------------------------------------ opening the game

    def open_game
      say(nil, "Player #{first_player + 1} goes first.")
      2.times { |seat| deal_opening_hand(seat) }
      # each mulligan lets the opponent draw an extra card
      2.times { |seat| draw(seat, player(opponent_of(seat))['mulligans']) }
    end

    def deal_opening_hand(seat)
      p = player(seat)
      shuffle(seat)

      100.times do
        draw(seat, HAND_SIZE)
        return if p['hand'].any? { |uid| card(uid).basic_pokemon? }

        p['mulligans'] += 1
        say(seat, "Player #{seat + 1} has no Basic Pokémon and draws a new hand.")
        p['deck'].concat(p['hand'])
        p['hand'] = []
        shuffle(seat)
      end
      raise ArgumentError, "Deck of seat #{seat} has no Basic Pokémon"
    end

    def shuffle(seat)
      return unless @shuffle

      player(seat)['deck'] = player(seat)['deck'].shuffle(random: @rng)
    end

    # ------------------------------------------------------------------ checks

    def check_setup(seat, action)
      p = player(seat)
      return 'Setup is over.' unless phase == 'setup'
      return 'You have already placed your Pokémon.' if p['setup_done']

      active = action['active']
      bench = Array(action['bench'])
      return 'Choose a Basic Pokémon for the Active Spot.' if active.nil?

      chosen = [active, *bench]
      return 'Those cards are not all in your hand.' unless chosen.uniq.size == chosen.size && chosen.all? { |uid| p['hand'].include?(uid) }
      return 'Only Basic Pokémon can be placed.' unless chosen.all? { |uid| card(uid).basic_pokemon? }
      return "The Bench holds at most #{BENCH_SIZE} Pokémon." if bench.size > BENCH_SIZE

      nil
    end

    def check_bench(seat, action)
      p = player(seat)
      return 'That card is not in your hand.' unless p['hand'].include?(action['card'])
      return 'Only a Basic Pokémon can be put on the Bench.' unless card(action['card']).basic_pokemon?
      return "Your Bench is full (#{BENCH_SIZE})." if p['bench'].size >= BENCH_SIZE

      nil
    end

    def check_attach(seat, action)
      p = player(seat)
      return 'That card is not in your hand.' unless p['hand'].include?(action['card'])
      return 'Only an Energy card can be attached.' unless card(action['card']).energy?
      return 'You already attached an Energy this turn.' if p['flags']['energy']
      return 'Choose one of your Pokémon.' unless slot_at(seat, action['target'])

      nil
    end

    def check_evolve(seat, action)
      p = player(seat)
      return 'That card is not in your hand.' unless p['hand'].include?(action['card'])

      evolution = card(action['card'])
      return 'That card is not an evolution.' unless evolution.pokemon? && !evolution.basic_pokemon?

      slot = slot_at(seat, action['target'])
      return 'Choose one of your Pokémon.' unless slot
      return "You can't evolve a Pokémon on your first turn." if p['turns_taken'] <= 1
      return "A Pokémon can't evolve in the turn it was played or evolved." if slot['since'] >= turn_number && !evolve_at_once?(seat, slot, evolution)
      return "#{evolution.name} doesn't evolve from #{top_card(slot).name}." unless evolution.evolves_from == top_card(slot).name

      nil
    end

    # A Stadium may let a Pokémon evolve in the turn it was played (never one that evolved already).
    def evolve_at_once?(seat, slot, evolution)
      return false if slot['evolved'] == turn_number || player(seat)['turns_taken'] <= 1

      stadium_ops('evolve_at_once').any? do |op|
        top_card(slot).energy_types.include?(op['type']) && evolution.energy_types.include?(op['type'])
      end
    end

    def retreat_cost(seat)
      slot = active(seat)
      return 0 if slot['energy'].empty? && passive_ops(slot, 'free_retreat_without_energy').any?

      [top_card(slot).retreat_cost.to_i - tool_ops(slot, 'retreat_less').sum { |op| op['amount'] }, 0].max
    end
    public :retreat_cost

    def check_retreat(seat, action)
      p = player(seat)
      return 'You already retreated this turn.' if p['flags']['retreat']
      return 'There is no Pokémon on the Bench to switch with.' if p['bench'].empty?
      return 'Choose a Benched Pokémon.' unless p['bench'][action['to'].to_i] && action['to'].is_a?(Integer)

      return "#{top_card(p['active']).name} is #{condition?(p['active'], 'asleep') ? 'Asleep' : 'Paralyzed'} and can't retreat." if (conditions(p['active']) & %w[asleep paralyzed]).any?

      return "#{top_card(p['active']).name} can't retreat right now." if marks_of(p['active'], 'no_retreat').any?

      cost = retreat_cost(seat)
      paid = Array(action['energy'])
      return "Retreating costs #{cost} Energy." unless paid.size == cost && paid.uniq.size == cost
      return 'Discard Energy that is attached to your Active Pokémon.' unless paid.all? { |uid| p['active']['energy'].include?(uid) }

      nil
    end

    def check_attack(seat, action)
      p = player(seat)
      return "The player who goes first can't attack on the first turn." if turn_number == 1

      attacker = top_card(p['active'])
      attack = attacker.attacks[action['index'].to_i] if action['index'].is_a?(Integer) && action['index'] >= 0
      return 'Choose one of the attacks.' unless attack
      return "#{attack['name']} has an effect that is not available yet." if attack['has_effect']
      return "#{attacker.name} can't attack right now." if marks_of(p['active'], 'no_attack').any? { |mark| mark['name'].nil? || mark['name'] == attack['name'] }
      return "#{attacker.name} is #{condition?(p['active'], 'asleep') ? 'Asleep' : 'Paralyzed'} and can't attack." if (conditions(p['active']) & %w[asleep paralyzed]).any?
      return "Not enough Energy for #{attack['name']}." unless EnergyCost.payable?(attached_types(p['active']), attack['cost'])

      nil
    end

    def check_end_turn(_seat, _action)
      nil
    end

    def check_promote(seat, action)
      return 'There is nothing to promote.' unless pending && pending['seat'] == seat

      index = action['index']
      return 'Choose a Pokémon from your Bench.' unless index.is_a?(Integer) && bench(seat)[index]

      nil
    end

    def check_switch(seat, action)
      return 'There is nothing to switch.' unless pending && pending['type'] == 'switch' && pending['seat'] == seat
      return nil if action['skip'] && pending['optional']

      index = action['index']
      return 'Choose a Pokémon from the Bench.' unless index.is_a?(Integer) && bench(pending['side'])[index]

      nil
    end

    # ------------------------------------------------------------------ actions

    def do_setup(seat, action)
      p = player(seat)
      [action['active'], *Array(action['bench'])].each { |uid| p['hand'].delete(uid) }
      p['active'] = new_slot(action['active'], since: 0)
      p['bench'] = Array(action['bench']).map { |uid| new_slot(uid, since: 0) }
      p['setup_done'] = true
      say(seat, "Player #{seat + 1} placed their Pokémon.")

      begin_play if state['players'].all? { |other| other['setup_done'] }
    end

    def do_bench(seat, action)
      p = player(seat)
      p['hand'].delete(action['card'])
      p['bench'] << new_slot(action['card'], since: turn_number)
      say(seat, "Player #{seat + 1} put #{card(action['card']).name} on the Bench.")
      on_benched(seat, p['bench'].last)
      sweep_knockouts(by: seat)
    end

    def do_attach(seat, action)
      p = player(seat)
      slot = slot_at(seat, action['target'])
      p['hand'].delete(action['card'])
      slot['energy'] << action['card']
      p['flags']['energy'] = true
      say(seat, "Player #{seat + 1} attached #{card(action['card']).name} to #{top_card(slot).name}.")
    end

    def do_evolve(seat, action)
      p = player(seat)
      slot = slot_at(seat, action['target'])
      before = top_card(slot).name
      p['hand'].delete(action['card'])
      slot['stack'] << action['card']
      slot['since'] = turn_number
      slot['evolved'] = turn_number
      cure_all(slot)
      say(seat, "Player #{seat + 1} evolved #{before} into #{card(action['card']).name}.")
      trigger_on_evolve(seat, slot)
    end

    def do_retreat(seat, action)
      p = player(seat)
      old = p['active']
      action['energy'].each do |uid|
        old['energy'].delete(uid)
        p['discard'] << uid
      end
      index = action['to']
      p['active'] = p['bench'][index]
      p['bench'][index] = old
      cure_all(old)
      p['active']['moved_up'] = turn_number
      p['flags']['retreat'] = true
      say(seat, "Player #{seat + 1} retreated #{top_card(old).name}. #{top_card(p['active']).name} is now Active.")
    end

    def do_attack(seat, action)
      attacker = active(seat)
      attacker_card = top_card(attacker)
      attack = attacker_card.attacks[action['index']]
      say(seat, "#{attacker_card.name} used #{attack['name']}.")

      if condition?(attacker, 'confused') && !flip(seat, "for #{attacker_card.name}'s Confusion")
        attacker['damage'] += CONFUSION_DAMAGE
        say(seat, "#{attacker_card.name} hurt itself in its Confusion for #{CONFUSION_DAMAGE} damage.")
        sweep_knockouts(by: seat)
        return after_turn(seat)
      end

      switch = resolve_attack(seat, attack)
      sweep_knockouts(by: seat)
      return if finished?

      # a search the attack asks for
      if switch && switch['search'] && promotions_needed.empty? && active(seat)
        start_search(seat, switch['search'], after: seat)
        return
      end

      # a switch the attack asks for is made after the Knock Outs have been dealt with
      if switch && switch['chooser'] && promotions_needed.empty? && active(seat) && bench(switch['side']).any? && active(switch['side'])
        state['pending'] = { 'type' => 'switch', 'seat' => switch['chooser'], 'side' => switch['side'],
                             'optional' => switch['optional'], 'ended' => seat, 'stage' => 'attack' }
        return
      end

      after_turn(seat)
    end

    def do_end_turn(seat, _action)
      say(seat, "Player #{seat + 1} ended their turn.")
      after_turn(seat)
    end

    def do_promote(seat, action)
      p = player(seat)
      p['active'] = p['bench'].delete_at(action['index'])
      p['active']['moved_up'] = turn_number
      say(seat, "#{top_card(p['active']).name} is the new Active Pokémon.")

      if pending['queue'].any?
        pending['seat'] = pending['queue'].shift
        return
      end

      ended = pending['ended']
      stage = pending['stage']
      state['pending'] = nil
      stage == 'checkup' ? after_turn(ended) : start_turn(opponent_of(ended))
    end

    def do_switch(seat, action)
      pend = pending
      state['pending'] = nil
      if action['skip']
        say(seat, "Player #{seat + 1} chose not to switch.")
      else
        switch_active(pend['side'], action['index'])
      end
      after_turn(pend['ended']) if pend['stage'] == 'attack'
    end

    def do_concede(seat, _action)
      say(seat, "Player #{seat + 1} conceded.")
      finish(opponent_of(seat), 'concede')
    end

    # ------------------------------------------------------------------ turns and results

    def begin_play
      2.times do |seat|
        p = player(seat)
        p['prizes'] = p['deck'].shift(PRIZE_CARDS)
      end
      state['phase'] = 'play'
      say(nil, 'Both players set aside 6 Prize cards. The game begins.')
      start_turn(first_player)
    end

    def start_turn(seat)
      state['turn_number'] += 1
      state['current'] = seat
      p = player(seat)
      p['turns_taken'] += 1
      p['flags'] = { 'energy' => false, 'retreat' => false, 'supporter' => false, 'stadium' => false, 'abilities' => [] }

      if p['deck'].empty?
        say(seat, "Player #{seat + 1} has no card to draw.")
        return finish(opponent_of(seat), 'deck_out')
      end

      draw(seat, 1)
      say(seat, "Player #{seat + 1}'s turn. They drew a card.")
    end

    # Every Pokémon with no HP left is Knocked Out: it and what is attached go to the discard
    # pile and the opponent takes Prize cards. A player left with nothing in play loses.
    def sweep_knockouts(by:)
      [opponent_of(by), by].each do |seat|
        p = player(seat)
        fallen_slots = slots(seat).select { |slot| hp_left(slot) <= 0 }
        fallen_slots.each do |slot|
          fallen = top_card(slot)
          p['discard'].concat(slot['stack'], slot['energy'], Array(slot['tool']))
          if p['active'].equal?(slot)
            p['active'] = nil
          else
            p['bench'].delete_if { |other| other.equal?(slot) }
          end
          say(opponent_of(seat), "#{fallen.name} was Knocked Out.")
          take_prizes(opponent_of(seat), fallen.prize_value)
          return if finished?
        end
      end

      [by, opponent_of(by)].each do |seat|
        next unless slots(seat).empty?

        say(seat, "Player #{seat + 1} has no Pokémon left in play.")
        return finish(opponent_of(seat), 'no_pokemon')
      end
    end

    # The turn of +ended+ is over: Pokémon Checkup, then the other player's turn begins. Anyone
    # whose Active Pokémon was Knocked Out chooses a new one first.
    def after_turn(ended)
      return if finished?
      return await_promotions(ended, 'checkup') if promotions_needed.any?

      run_checkup(ended)
      return if finished?
      return await_promotions(ended, 'start') if promotions_needed.any?

      start_turn(opponent_of(ended))
    end

    def promotions_needed
      [0, 1].select { |seat| active(seat).nil? && bench(seat).any? }
    end

    def await_promotions(ended, stage)
      seats = promotions_needed
      state['pending'] = { 'type' => 'promote', 'seat' => seats.first, 'queue' => seats.drop(1),
                           'ended' => ended, 'stage' => stage }
    end

    # The Benched Pokémon at +index+ comes into the Active Spot, the old Active goes to the Bench.
    def switch_active(seat, index)
      p = player(seat)
      old = p['active']
      p['active'] = p['bench'][index]
      p['bench'][index] = old
      cure_all(old)
      p['active']['moved_up'] = turn_number
      say(seat, "#{top_card(p['active']).name} is now Active for Player #{seat + 1}.")
    end

    def take_prizes(seat, count)
      p = player(seat)
      taken = p['prizes'].pop([count, p['prizes'].size].min)
      p['hand'].concat(taken)
      say(seat, "Player #{seat + 1} took #{taken.size} Prize #{taken.size == 1 ? 'card' : 'cards'}.")
      finish(seat, 'prizes') if p['prizes'].empty?
    end

    def finish(seat, reason)
      state['phase'] = 'finished'
      state['winner'] = seat
      state['win_reason'] = reason
      state['pending'] = nil
      say(seat, "Player #{seat + 1} wins.")
    end

    # ------------------------------------------------------------------ helpers

    def new_slot(uid, since:)
      { 'stack' => [uid], 'energy' => [], 'damage' => 0, 'since' => since, 'conditions' => [] }
    end

    def draw(seat, count)
      p = player(seat)
      p['hand'].concat(p['deck'].shift(count))
    end

    def say(seat, text)
      state['log'] << { 'turn' => turn_number, 'seat' => seat, 'text' => text }
      state['log'].shift while state['log'].size > LOG_LIMIT
    end

    # ------------------------------------------------------------------ listing actions

    def candidates(seat)
      return setup_candidates(seat) if phase == 'setup'
      return pending_search_candidates(seat) if pending && pending['type'] == 'search'
      return pending_candidates(seat) if pending
      return [{ 'type' => 'concede' }] unless seat == current

      play_candidates(seat) + [{ 'type' => 'concede' }]
    end

    def setup_candidates(seat)
      hand_basics = unique_by_card(player(seat)['hand']).select { |uid| card(uid).basic_pokemon? }
      all_basics = player(seat)['hand'].select { |uid| card(uid).basic_pokemon? }

      hand_basics.map do |uid|
        { 'type' => 'setup', 'active' => uid, 'bench' => (all_basics - [uid]).first(BENCH_SIZE) }
      end + [{ 'type' => 'concede' }]
    end

    def pending_candidates(seat)
      return [{ 'type' => 'concede' }] unless pending['seat'] == seat

      choices = bench(pending['type'] == 'switch' ? pending['side'] : seat).each_index.map { |index| { 'type' => pending['type'], 'index' => index } }
      choices << { 'type' => 'switch', 'skip' => true } if pending['type'] == 'switch' && pending['optional']
      choices + [{ 'type' => 'concede' }]
    end

    def play_candidates(seat)
      p = player(seat)
      hand = unique_by_card(p['hand'])
      targets = ['active'] + p['bench'].each_index.map { |index| "bench-#{index}" }
      actions = []

      actions.concat(trainer_candidates(seat))
      actions.concat(ability_candidates(seat))
      hand.each do |uid|
        actions << { 'type' => 'bench', 'card' => uid }
        targets.each do |target|
          actions << { 'type' => 'attach', 'card' => uid, 'target' => target }
          actions << { 'type' => 'evolve', 'card' => uid, 'target' => target }
        end
      end

      if p['active']
        cost = retreat_cost(seat)
        p['bench'].each_index do |index|
          p['active']['energy'].combination(cost).each { |paid| actions << { 'type' => 'retreat', 'to' => index, 'energy' => paid } }
        end
        top_card(p['active']).attacks.each_index { |index| actions << { 'type' => 'attack', 'index' => index } }
      end

      actions << { 'type' => 'end_turn' }
    end

    # One uid per distinct card, so a hand of five Fire Energy lists the action once.
    def unique_by_card(uids)
      uids.uniq { |uid| state['cards'][uid] }
    end
  end
end
