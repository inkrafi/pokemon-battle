class GamesController < ApplicationController
  before_action :set_game, only: [:show, :actions, :reveal]
  before_action :set_waiting_game, only: [:invite, :join]

  def index
    @games = Game.of(current_player).order(updated_at: :desc)
  end

  def new
    @decks = available_decks
    @mode = params[:mode].presence_in(Game::LOCAL_MODES) || 'bot'
  end

  def create
    @mode = params[:mode].presence_in(Game::LOCAL_MODES) || 'bot'
    @decks = available_decks
    chosen = [params[:deck0], params[:deck1]].map { |id| @decks.find { |deck| deck.id == id.to_i } }

    if chosen.any?(&:nil?)
      flash.now[:danger] = 'Choose a legal deck for each side.'
      return render('new', status: :unprocessable_entity)
    end

    players = @mode == 'bot' ? [current_player, nil] : [current_player, current_player]
    game = Game.start!(decks: chosen, players: players, mode: @mode)
    redirect_to game_path(game)
  end

  # Opens an online game and shows the link to send to a friend.
  def online
    deck = available_decks.find { |candidate| candidate.id == params[:deck0].to_i }
    return redirect_to(new_game_path, flash: { danger: 'Choose a legal deck first.' }) unless deck

    redirect_to game_path(Game.open_online!(deck: deck, host: current_player))
  end

  # What a friend sees when they open the invite link: pick a deck and join.
  def invite
    return redirect_to(game_path(@game)) if @game.player0_id == current_player.id

    @decks = available_decks
  end

  def join
    deck = available_decks.find { |candidate| candidate.id == params[:deck].to_i }
    return redirect_to(join_game_path(@game.invite_token), flash: { danger: 'Choose a legal deck first.' }) unless deck

    @game.join!(player: current_player, deck: deck)
    redirect_to game_path(@game)
  rescue Game::JoinError => error
    redirect_to join_game_path(@game.invite_token), flash: { danger: error.message }
  end

  # The board. In a game on one screen it only shows a hand to the player whose turn it is, and
  # a hand-over screen in between.
  def show
    return render('waiting') if @game.waiting?

    @board = GameBoard.new(@game, viewer: visible_seat)
  end

  # Every move comes through here. The page sends the version of the board it was drawn from, so
  # a move from an out-of-date page is refused instead of being played on a different board.
  def actions
    seat = holding_seat
    message =
      if @game.waiting?
        'Wait for your opponent to join first.'
      elsif params[:version] != @game.version && !placing_pokemon?
        'The board changed since this page was drawn. Look at it again and retry.'
      elsif seat.nil?
        'Show your side of the table first.'
      else
        play(seat)
      end

    flash[:danger] = message if message
    # a move sent in the background gets a Turbolinks visit (it replaces this page in the history)
    redirect_to game_path(@game), turbolinks: :replace
  end

  # Whoever picks up the device says who they are, but only the player who has to act can.
  def reveal
    if @game.seats_of(current_player).size == 2 && !@game.finished?
      seat_memory[@game.id.to_s] = @game.engine.seat_to_act
      save_seat_memory
    end
    redirect_to game_path(@game), turbolinks: :replace
  end

  private

  def set_game
    @game = Game.of(current_player).find(params[:id])
  end

  # The game an invite link points to, while it still waits for a second player. Somebody who is
  # already in the game goes to it instead.
  def set_waiting_game
    @game = Game.find_by!(invite_token: params[:token])
    return if @game.waiting?

    redirect_to(@game.seats_of(current_player).any? ? game_path(@game) : games_path, flash: { danger: 'This game already has two players.' })
  end

  # Placing the first Pokémon doesn't depend on what the board looks like: online, the other
  # player may well place theirs while this page is open, which changes the version.
  def placing_pokemon?
    params[:type] == 'setup' && @game.status == 'setup'
  end

  # Plays the move; returns why it was refused, or nil.
  def play(seat)
    @game.perform!(seat, action_from_params)
    hand_over_if_needed(seat)
    nil
  rescue Tcg::IllegalAction => error
    error.message
  end

  # Decks that can be played: the sample decks and the guest's own legal decks.
  def available_decks
    Deck.samples.includes(deck_cards: :card).to_a + current_player.decks.includes(deck_cards: :card).select(&:legal?)
  end

  # The seat whose screen this is. Someone with a single seat always sees that one; with both
  # seats (one screen) it is whoever last said "I am Player N".
  def holding_seat
    seats = @game.seats_of(current_player)
    seats.one? ? seats.first : seat_memory[@game.id.to_s]
  end

  # The same, but only while that player is the one who has to act, so nobody sees a hand that
  # isn't theirs to play. A finished game is shown to nobody in particular.
  def visible_seat
    return nil if @game.finished?

    seat = holding_seat
    return seat if @game.seats_of(current_player).one?

    seat if seat == @game.engine.seat_to_act
  end

  def hand_over_if_needed(seat)
    return unless @game.seats_of(current_player).size == 2

    seat_memory.delete(@game.id.to_s) unless @game.engine.seat_to_act == seat
    save_seat_memory
  end

  def seat_memory
    @seat_memory ||= (session[:game_seats] || {}).dup
  end

  def save_seat_memory
    session[:game_seats] = seat_memory.to_a.last(10).to_h
  end

  # The fields of a Trainer card or an Ability: numbers, names of places on the table and lists.
  def choices_from_params(type, number)
    action = { 'type' => type }
    %w[card index opp to pick energy with].each { |key| action[key] = number.call(params[key]) if params[key].present? }
    %w[target to_target slot].each { |key| action[key] = params[key].to_s if params[key].present? }
    action['discard'] = Array(params[:discard]).filter_map { |uid| number.call(uid) } if params[:discard].present?
    action
  end

  def action_from_params
    number = ->(value) { Integer(value.to_s, exception: false) }
    type = params[:type].to_s

    case type
    when 'setup'
      active = number.call(params[:active])
      { 'type' => type, 'active' => active, 'bench' => Array(params[:bench]).filter_map { |uid| number.call(uid) } - [active] }
    when 'bench'
      { 'type' => type, 'card' => number.call(params[:card]) }
    when 'attach', 'evolve'
      { 'type' => type, 'card' => number.call(params[:card]), 'target' => params[:target].to_s }
    when 'retreat'
      { 'type' => type, 'to' => number.call(params[:to]), 'energy' => Array(params[:energy]).filter_map { |uid| number.call(uid) } }
    when 'attack', 'promote'
      { 'type' => type, 'index' => number.call(params[:index]) }
    when 'switch'
      params[:skip].present? ? { 'type' => type, 'skip' => true } : { 'type' => type, 'index' => number.call(params[:index]) }
    when 'choose'
      { 'type' => type, 'cards' => Array(params[:cards]).filter_map { |uid| number.call(uid) } }
    when 'play', 'ability'
      choices_from_params(type, number)
    else
      { 'type' => type }
    end
  end
end
