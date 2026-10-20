# A game in progress or finished. The board is a JSON document owned by Tcg::Engine; this
# record stores it and says who is sitting where.
#
# Modes:
#   hotseat  one person holds both seats on a single screen (player0 and player1 are the same guest)
#   bot      seat 1 is played by the computer (player1 stays empty)
#   online   two guests on their own devices; the game is "waiting" until the second one joins
#            through the invite link
class Game < ApplicationRecord
  STATUSES = %w[waiting setup play finished].freeze
  MODES = %w[hotseat bot online].freeze
  LOCAL_MODES = %w[hotseat bot].freeze # the ones started from the new game form with both decks
  BOT_SEAT = 1
  BOT_ACTION_LIMIT = 1000

  belongs_to :player0, class_name: 'Player', optional: true
  belongs_to :player1, class_name: 'Player', optional: true
  belongs_to :host_deck, class_name: 'Deck', optional: true

  has_secure_token :invite_token

  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  scope :of, ->(player) { where(player0: player).or(where(player1: player)) }

  # Starts a game from two legal decks.
  def self.start!(decks:, players: [nil, nil], mode: 'hotseat', first_player: nil, rng: Random.new, shuffle: true)
    illegal = decks.find { |deck| !deck.legal? }
    raise ArgumentError, "#{illegal.name} isn't a legal deck: #{illegal.problems.first}" if illegal

    engine = Tcg::Engine.start(decks: decks.map(&:card_ids), first_player: first_player, rng: rng, shuffle: shuffle)
    create!(state: engine.state, status: engine.phase, mode: mode, player0: players[0], player1: players[1])
  end

  # Opens an online game for +host+ with their deck. It starts when somebody joins.
  def self.open_online!(deck:, host:)
    raise ArgumentError, "#{deck.name} isn't a legal deck: #{deck.problems.first}" unless deck.legal?

    create!(mode: 'online', status: 'waiting', player0: host, host_deck: deck)
  end

  # The second player sits down with their deck and the game starts. A coin flip decides who goes first.
  def join!(player:, deck:, first_player: nil, shuffle: true)
    with_lock do
      raise JoinError, 'This game already has two players.' unless waiting?
      raise JoinError, 'You are the host of this game. Send the link to somebody else.' if player0_id == player.id
      raise JoinError, "#{deck.name} isn't a legal deck: #{deck.problems.first}" unless deck.legal?
      raise JoinError, 'The host removed their deck. Ask them to start a new game.' unless host_deck

      engine = Tcg::Engine.start(decks: [host_deck.card_ids, deck.card_ids], first_player: first_player, rng: rng, shuffle: shuffle)
      update!(state: engine.state, status: engine.phase, player1: player, host_deck: nil)
    end
    self
  end

  class JoinError < StandardError; end

  def waiting?
    status == 'waiting'
  end

  def online?
    mode == 'online'
  end

  def finished?
    status == 'finished'
  end

  def bot?
    mode == 'bot'
  end

  def bot_seats
    bot? ? [BOT_SEAT] : []
  end

  # The seat a guest sits in. When one guest holds both seats (hotseat), both are returned.
  def seats_of(player)
    [0, 1].select { |seat| player && send("player#{seat}_id") == player.id }
  end

  # Where chance comes from (coin flips, shuffles). Tests give it a fixed one.
  attr_writer :rng

  def rng
    @rng ||= Random.new
  end

  # The rules engine on a copy of the saved board, so a failed move leaves the game untouched.
  def engine
    raise 'This game has not started yet.' if waiting?

    Tcg::Engine.new(JSON.parse(state.to_json), rng: rng)
  end

  # Changes whenever the board does. A page remembers the one it was drawn from, so a move made
  # from an out-of-date page (a second tab, a double click) can be recognised.
  def version
    updated_at.utc.iso8601(6)
  end

  # Everybody watching this game (an online game has two pages open) is told that the board changed.
  # They ask for their own view: nothing secret travels in the message.
  after_commit :announce_change, on: [:create, :update]

  # Plays one move and saves the board. The row is locked while it happens, so two moves at the
  # same moment (a double click, a second tab) are played one after the other. In a game against
  # the computer, its replies are played right after.
  def perform!(seat, action)
    with_lock do
      game = engine
      game.perform(seat, action)
      play_bot_moves(game)
      update!(state: game.state, status: game.phase, winner_seat: game.winner)
    end
    self
  end

  private

  def announce_change
    GameChannel.broadcast_to(self, { version: version }) if online?
  end

  def play_bot_moves(game)
    bot = Tcg::RandomBot.new(rng: rng)
    BOT_ACTION_LIMIT.times do
      seat = game.seat_to_act
      return unless seat && bot_seats.include?(seat)

      game.perform(seat, bot.choose(game, seat))
    end
  end
end
