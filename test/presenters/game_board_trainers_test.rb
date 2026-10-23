require "test_helper"

# What the board offers for Trainer cards, searches, switches, Abilities and Special Conditions.
class GameBoardTrainersTest < ActiveSupport::TestCase
  setup do
    @player = Player.create!
    @deck = build_legal_deck(player: @player)
    @game = Game.start!(decks: [@deck, @deck], players: [@player, @player], first_player: 0, shuffle: false)
    2.times { |seat| place(seat) }
    draw_for(@game)
  end

  def board(viewer = 0)
    GameBoard.new(@game.reload, viewer: viewer)
  end

  def place(seat)
    engine = @game.reload.engine
    active = engine.player(seat)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    @game.perform!(seat, 'type' => 'setup', 'active' => active, 'bench' => [])
  end

  # Adds a card to the game, in a hand when +seat+ is given. Returns its uid.
  def add_card(card, seat: nil)
    engine = @game.reload.engine
    engine.catalog[card.id] = card
    engine.state['cards'] << card.id
    uid = engine.state['cards'].size - 1
    engine.player(seat)['hand'] << uid if seat
    @game.update!(state: engine.state)
    uid
  end

  def bench_a_basic
    @game.perform!(0, 'type' => 'bench', 'card' => board(0).hand.find { |entry| entry.card.basic_pokemon? }.uid)
  end

  def nothing_trainer
    make_trainer('Nothing', 'item', { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => 'Fire', 'amount' => 0, 'turns' => 0 })
  end

  test "a Trainer card that needs a choice lists it, one that needs none lists nothing to fill in" do
    bench_a_basic
    switch = add_card(make_trainer('Swap', 'item', { 'op' => 'switch_own' }), seat: 0)
    nothing = add_card(nothing_trainer, seat: 0)

    assert_equal ['to'], board(0).play_fields(switch).map { |field| field['field'] }
    assert_equal [], board(0).play_fields(nothing)
    assert_nil board(1).play_fields(switch) # not their turn
  end

  test "a Trainer card that can't be played now has no form" do
    heal = add_card(make_trainer('Heal', 'supporter', { 'op' => 'heal', 'amount' => 30 }), seat: 0)

    assert_nil board(0).play_fields(heal) # nothing is damaged
  end

  test "a search lists the cards of the deck and which of them fit" do
    ball = add_card(make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'energy' }] }), seat: 0)

    @game.perform!(0, 'type' => 'play', 'card' => ball)
    view = board(0)

    assert view.searching?
    assert_equal 1, view.search_limit
    assert view.search_options.any?(&:fits)
    assert view.search_options.any? { |option| !option.fits }
    assert_not board(1).searching?
    assert_equal [], board(1).search_options
    assert_match(/searching their deck/, board(1).why_seat_acts)
  end

  test "choosing which Pokémon to switch in is a state of its own" do
    repel = add_card(make_trainer('Repel', 'item', { 'op' => 'switch_opponent' }), seat: 0)
    engine = @game.reload.engine
    basic = engine.player(1)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    engine.player(1)['hand'].delete(basic)
    engine.bench(1) << { 'stack' => [basic], 'energy' => [], 'damage' => 0, 'since' => 0, 'conditions' => [] }
    @game.update!(state: engine.state)

    @game.perform!(0, 'type' => 'play', 'card' => repel)

    assert board(1).switching?
    assert_not board(1).switch_optional?
    assert_not board(0).switching?
    assert_match(/switch in/, board(1).why_seat_acts)
  end

  test "the Abilities that can be used are offered for the Pokémon that has them" do
    ability = { 'name' => 'Errand', 'kind' => 'Ability', 'trigger' => 'activated', 'needs' => {}, 'effects' => [{ 'op' => 'draw', 'count' => 1 }], 'supported' => true }
    uid = add_card(make_card(name: 'Drawer', hp: 100, attacks: [attack], abilities: [ability]))
    engine = @game.reload.engine
    engine.active(0)['stack'] = [uid]
    @game.update!(state: engine.state)

    assert_equal [[0, 'Errand', []]], board(0).usable_abilities('active')
    assert_equal [], board(1).usable_abilities('active')
  end

  test "slots show Special Conditions and the Tool attached" do
    tool = add_card(make_trainer('Gadget', 'tool', { 'op' => 'tool', 'kind' => 'retreat_less', 'amount' => 1 }))
    engine = @game.reload.engine
    engine.active(1)['conditions'] = %w[poisoned confused]
    engine.active(1)['tool'] = tool
    @game.update!(state: engine.state)

    view = board(0).active(1)

    assert_equal %w[poisoned confused], view.conditions
    assert_equal 'Gadget', view.tool.name
  end

  test "the Stadium in play and who put it there" do
    garden = add_card(make_trainer('Garden', 'stadium', { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => 'Fire', 'amount' => 10 }))
    engine = @game.reload.engine
    engine.state['stadium'] = { 'uid' => garden, 'owner' => 1 }
    @game.update!(state: engine.state)

    stadium = board.stadium

    assert_equal ['Garden', 1], [stadium[:card].name, stadium[:owner]]
  end
end
