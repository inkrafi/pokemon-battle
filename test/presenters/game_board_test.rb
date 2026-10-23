require "test_helper"

class GameBoardTest < ActiveSupport::TestCase
  setup do
    @player = Player.create!
    @deck = build_legal_deck(player: @player)
    @game = Game.start!(decks: [@deck, @deck], players: [@player, @player], first_player: 0, shuffle: false)
  end

  def board(viewer = 0, game = @game)
    GameBoard.new(game.reload, viewer: viewer)
  end

  def place(seat)
    engine = @game.reload.engine
    active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    @game.perform!(seat, 'type' => 'setup', 'active' => active, 'bench' => [])
  end

  # Both players place their Pokémon and the first player draws the card that starts their turn.
  def start_play
    2.times { |seat| place(seat) }
    draw_for(@game)
  end

  def give_to_hand(seat, fixture)
    engine = @game.reload.engine
    engine.state['cards'] << cards(fixture).id
    uid = engine.state['cards'].size - 1
    engine.player(seat)['hand'] << uid
    @game.update!(state: engine.state)
    uid
  end

  test "during setup only the seat that has to place Pokémon is the one to act" do
    assert board.setup?
    assert_equal 0, board.acting_seat
    assert board.my_move?
    assert_not board(1).my_move?

    place(0)

    assert_equal 1, board(1).acting_seat
    assert_match(/places their Pokémon/, board(1).why_seat_acts)
  end

  test "setup offers the Basic Pokémon in the hand" do
    names = board.setup_basics.map { |entry| entry.card.name }

    assert_equal %w[Sprigling] * 4, names
  end

  test "the viewer sees their own hand and only the size of the other" do
    start_play

    assert_equal @game.engine.player(0)['hand'].size, board(0).hand.size
    assert_equal board(0).hand_count(1), board(1).hand.size
  end

  test "a Basic Pokémon can be benched on your turn, not on the other player's" do
    start_play
    uid = board(0).hand.find { |entry| entry.card.basic_pokemon? }.uid

    assert board(0).can_bench?(uid)
    assert_not board(1).can_bench?(uid)
  end

  test "an Energy card lists the Pokémon it can go on, with places in the names" do
    start_play
    @game.perform!(0, 'type' => 'bench', 'card' => board(0).hand.find { |entry| entry.card.basic_pokemon? }.uid)
    energy = give_to_hand(0, :grass_energy)

    assert_equal [['active', 'Sprigling (Active)'], ['bench-0', 'Sprigling (Bench 1)']], board(0).attach_targets(energy)
    assert_equal [], board(1).attach_targets(energy)
  end

  test "after the Energy is attached no more targets are offered this turn" do
    start_play
    first = give_to_hand(0, :grass_energy)
    second = give_to_hand(0, :grass_energy)
    @game.perform!(0, 'type' => 'attach', 'card' => first, 'target' => 'active')

    assert_empty board(0).attach_targets(second)
  end

  test "evolutions are offered once they are allowed" do
    start_play
    evolution = board(0).hand.find { |entry| entry.card.name == 'Bloomling' }.uid
    assert_empty board(0).evolve_targets(evolution) # nobody evolves on their first turn

    @game.perform!(0, 'type' => 'end_turn')
    draw_for(@game)
    @game.perform!(1, 'type' => 'end_turn')
    draw_for(@game)

    assert_equal [['active', 'Sprigling (Active)']], board(0).evolve_targets(evolution)
  end

  test "attacks say why they can't be used" do
    start_play

    assert_equal "The player who goes first can't attack on the first turn.", board(0).attack_error(0)
    assert_equal "It isn't your turn.", board(1).attack_error(0)
  end

  test "retreating is offered with a Benched Pokémon" do
    start_play
    assert_not board(0).can_retreat?

    @game.perform!(0, 'type' => 'bench', 'card' => board(0).hand.find { |entry| entry.card.basic_pokemon? }.uid)
    energy = give_to_hand(0, :grass_energy)
    @game.perform!(0, 'type' => 'attach', 'card' => energy, 'target' => 'active')

    assert board(0).can_retreat?
    assert_equal 1, board(0).retreat_cost
    assert_equal 1, board(0).active_energy.size
  end

  test "a turn starts with drawing a card, and the card drawn is known until it leaves the hand" do
    2.times { |seat| place(seat) }

    assert board(0).drawing?
    assert_not board(1).drawing?
    assert_not board(0).can_end_turn?
    assert_match(/by drawing a card/, board(1).why_seat_acts)
    assert_nil board(0).drawn_uid

    @game.perform!(0, 'type' => 'draw')

    assert_not board(0).drawing?
    assert_equal board(0).hand.last.uid, board(0).drawn_uid
    assert_nil board(1).drawn_uid
  end

  test "the turn can be ended by the player whose turn it is" do
    start_play

    assert board(0).can_end_turn?
    assert_not board(1).can_end_turn?
  end

  test "slots show the damage, the HP left and the Energy" do
    start_play
    engine = @game.engine
    engine.active(1)['damage'] = 20
    @game.update!(state: engine.state)

    view = board(0).active(1)

    assert_equal 'Sprigling', view.name
    assert_equal [60, 40], [view.hp, view.hp_left]
    assert_equal 67, view.hp_percent
    assert_not view.evolved?
    assert_empty board(0).bench(1)
  end

  test "a finished game names the winner and why" do
    start_play
    @game.perform!(1, 'type' => 'concede')
    result = board(nil)

    assert result.finished?
    assert_equal 'Player 1', result.winner_name
    assert_equal 'Player 1 won because the opponent conceded.', result.result_text
  end

  test "the feed numbers the log entries and says what kind each one is" do
    start_play
    feed = board.feed

    assert_equal feed.map { |entry| entry['n'] }.sort, feed.map { |entry| entry['n'] }
    assert_equal 'turn', feed.find { |entry| entry['text'] == "Player 1's turn." }['kind']
    assert_equal 'draw', feed.last['kind']
    assert_equal 'Your turn', board(0).turn_title(0)
    assert_equal "Player 1's turn", board(1).turn_title(0)
  end

  test "the log lists the latest events first" do
    start_play

    assert_equal 'Player 1 drew a card.', board.log.first['text']
    assert_equal "Player 1's turn.", board.log.second['text']
    assert_operator board.log.size, :<=, 14
  end
end
