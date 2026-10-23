# What one player sees of a game, and what they can click. It reads the engine and never makes
# rules of its own: every button comes from Tcg::Engine#error_for, so the screen and the rules
# can't disagree.
#
# +viewer+ is the seat whose screen this is (nil when nobody holds the device, for example on a
# hand-over screen or a finished game).
class GameBoard
  RESULT_REASONS = {
    'prizes' => 'took the last Prize card',
    'no_pokemon' => 'left the opponent with no Pokémon in play',
    'deck_out' => 'left the opponent without a card to draw',
    'concede' => 'won because the opponent conceded'
  }.freeze

  HandCard = Struct.new(:uid, :card)

  # A Pokemon in play, ready to draw.
  SlotView = Struct.new(:target, :slot, :card, :stack, :damage, :energy, :conditions, :tool, :abilities, keyword_init: true) do
    def name = card.name
    def hp = card.hp
    def hp_left = [card.hp - damage, 0].max
    def hp_percent = (hp_left.to_f / hp * 100).round
    def evolved? = stack.size > 1
  end

  # What the viewer can pick from in a search of the deck.
  SearchOption = Struct.new(:uid, :card, :fits)

  attr_reader :game, :engine, :viewer

  def initialize(game, viewer: nil)
    @game = game
    @engine = game.engine
    @viewer = viewer
  end

  # ---------------------------------------------------------------- the game as a whole

  def phase = engine.phase
  def setup? = phase == 'setup'
  def finished? = engine.finished?
  def acting_seat = engine.seat_to_act
  def turn_number = engine.turn_number
  def version = game.version
  def opponent = viewer && 1 - viewer
  def seat_name(seat) = "Player #{seat + 1}"

  # Whether the viewer has already put their Pokémon down (online, the other player may not have).
  def placed?
    !viewer.nil? && engine.player(viewer)['setup_done']
  end

  def my_move?
    !viewer.nil? && acting_seat == viewer
  end

  def pending_type = engine.pending && engine.pending['type']

  # The start of the viewer's turn: a card has to be drawn before anything else.
  def drawing?
    my_move? && pending_type == 'draw'
  end

  # The uid of the card the viewer drew at the start of this turn, while it is still in their hand.
  def drawn_uid
    drawn = viewer && engine.player(viewer)['drawn']
    return nil unless drawn && drawn['turn'] == turn_number && engine.player(viewer)['hand'].include?(drawn['uid'])

    drawn['uid']
  end

  # Choosing a new Active Pokémon after a Knock Out.
  def promoting?
    my_move? && pending_type == 'promote'
  end

  # Choosing which Benched Pokémon an effect brings into the Active Spot.
  def switching?
    my_move? && pending_type == 'switch'
  end

  def switch_optional?
    switching? && engine.pending['optional']
  end

  def searching?
    my_move? && pending_type == 'search'
  end

  # The cards a search may take, with whether each one fits what is looked for.
  def search_options
    return [] unless searching?

    engine.pending['source'].map do |uid|
      card = engine.card(uid)
      SearchOption.new(uid, card, engine.pending['filters'].any? { |filter| Tcg::CardFilter.match?(card, filter) })
    end
  end

  def search_limit = engine.pending['filters'].size
  def search_destination = engine.pending['to']

  # The Trainer card played, with the Stadium in play and who put it there.
  def stadium
    entry = engine.state['stadium']
    entry && { card: engine.card(entry['uid']), owner: entry['owner'] }
  end

  def winner_name
    seat_name(engine.winner)
  end

  def result_text
    "#{winner_name} #{RESULT_REASONS.fetch(engine.win_reason, 'won')}."
  end

  # What a hand-over screen says about whose go it is and why.
  def why_seat_acts
    if setup?
      'places their Pokémon.'
    elsif pending_type == 'draw'
      "starts turn #{engine.turn_number} by drawing a card."
    elsif pending_type == 'promote'
      'chooses a new Active Pokémon.'
    elsif pending_type == 'switch'
      'chooses which Pokémon to switch in.'
    elsif pending_type == 'search'
      'is searching their deck.'
    else
      "takes turn #{engine.turn_number}."
    end
  end

  def log(count = 14)
    engine.log.last(count).reverse
  end

  # What kind of event a log entry is, for the notifications on the page (games/_fx).
  LOG_KINDS = [
    [:win, / wins\.\z/], [:turn, /'s turn\.\z/], [:knockout, /Knocked Out|no Pokémon left/], [:prize, /took \d+ Prize/],
    [:coin, /flipped a coin/], [:attack, / used /], [:damage, /took \d+ damage|hurt itself/], [:heal, /healed/],
    [:condition, /is now (Poisoned|Burned|Asleep|Confused|Paralyzed)/], [:evolve, /evolved/],
    [:draw, /drew|searched their deck/], [:trainer, /played /], [:energy, /attached|Energy/],
    [:bench, /on the Bench|is now Active|new Active/], [:end, /ended their turn/]
  ].freeze

  # The latest log entries, oldest first, with their kind. Entries from before log entries were
  # numbered have no n and are left out.
  def feed(count = 30)
    engine.log.last(count).select { |entry| entry['n'] }.map do |entry|
      kind = LOG_KINDS.find { |_, pattern| entry['text'].match?(pattern) }&.first || :info
      entry.merge('kind' => kind.to_s)
    end
  end

  # The title of a turn banner for a seat: "Your turn" on the viewer's own screen.
  def turn_title(seat)
    seat == viewer ? 'Your turn' : "#{seat_name(seat)}'s turn"
  end

  # ---------------------------------------------------------------- zones

  def hand_count(seat) = engine.player(seat)['hand'].size
  def deck_count(seat) = engine.player(seat)['deck'].size
  def prizes_left(seat) = engine.player(seat)['prizes'].size
  def discard_cards(seat) = engine.player(seat)['discard'].map { |uid| engine.card(uid) }

  def hand
    engine.player(viewer)['hand'].map { |uid| HandCard.new(uid, engine.card(uid)) }
  end

  def active(seat)
    slot = engine.active(seat)
    slot && slot_view('active', slot)
  end

  def bench(seat)
    engine.bench(seat).each_with_index.map { |slot, index| slot_view("bench-#{index}", slot) }
  end

  # ---------------------------------------------------------------- what the viewer can do

  def setup_basics
    hand.select { |entry| entry.card.basic_pokemon? }
  end

  def can_bench?(uid)
    allowed?('type' => 'bench', 'card' => uid)
  end

  # [[target, name], ...] of the Pokemon this Energy card could go on.
  def attach_targets(uid) = targets_for('attach', uid)

  # [[target, name], ...] of the Pokemon this evolution card could evolve.
  def evolve_targets(uid) = targets_for('evolve', uid)

  # nil when the attack can be used, otherwise why not.
  def attack_error(index)
    return "It isn't your turn." unless my_move?

    engine.error_for(viewer, 'type' => 'attack', 'index' => index)
  end

  def can_retreat?
    my_move? && legal_actions.any? { |action| action['type'] == 'retreat' }
  end

  def retreat_cost
    engine.retreat_cost(viewer)
  end

  # The Energy on the Active Pokemon, to choose from when retreating.
  def active_energy
    engine.active(viewer)['energy'].map { |uid| [uid, engine.card(uid)] }
  end

  # The fields to fill in to play a Trainer card now: [] for a card that needs none, nil when the
  # card can't be played at all.
  def play_fields(uid)
    return nil unless my_move? && legal_actions.any? { |action| action['type'] == 'play' && action['card'] == uid }

    engine.play_fields(viewer, uid)
  end

  # [[index, name, fields], ...] of the Abilities of one of the viewer's Pokémon that can be used now.
  def usable_abilities(target)
    return [] unless my_move?

    slot = engine.slot_at(viewer, target)
    legal_actions.select { |action| action['type'] == 'ability' && action['slot'] == target }.map { |action| action['index'] }.uniq.map do |index|
      ability = engine.top_card(slot).abilities.select { |entry| entry['supported'] }[index]
      [index, ability['name'], engine.ability_fields(viewer, ability)]
    end
  end

  def can_end_turn?
    my_move? && engine.pending.nil? && phase == 'play'
  end

  private

  # Computed once: listing every legal move is the expensive part of drawing a board.
  def legal_actions
    @legal_actions ||= engine.legal_actions(viewer)
  end

  def slot_view(target, slot)
    SlotView.new(target: target, slot: slot, card: engine.top_card(slot),
                 stack: slot['stack'].map { |uid| engine.card(uid) },
                 damage: slot['damage'], energy: slot['energy'].map { |uid| engine.card(uid) },
                 conditions: Array(slot['conditions']), tool: slot['tool'] && engine.card(slot['tool']),
                 abilities: engine.top_card(slot).abilities.map { |ability| ability['name'] })
  end

  def allowed?(action)
    my_move? && engine.error_for(viewer, action).nil?
  end

  def targets_for(type, uid)
    return [] unless my_move?

    targets = ['active'] + engine.bench(viewer).each_index.map { |index| "bench-#{index}" }
    targets.select { |target| allowed?('type' => type, 'card' => uid, 'target' => target) }
           .map { |target| [target, target_label(target)] }
  end

  # "Vulpix (Active)" or "Vulpix (Bench 2)": two Pokémon can share a name.
  def target_label(target)
    name = engine.top_card(engine.slot_at(viewer, target)).name
    place = target == 'active' ? 'Active' : "Bench #{target.split('-').last.to_i + 1}"
    "#{name} (#{place})"
  end
end
