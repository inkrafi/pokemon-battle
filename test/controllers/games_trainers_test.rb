require "test_helper"

# Trainer cards, searches, switches and Abilities played through the page.
class GamesTrainersTest < ActionDispatch::IntegrationTest
  setup do
    @water = build_legal_deck(name: 'Water starter', sample: true)
    @grass = build_legal_deck(name: 'Grass starter', sample: true)
  end

  # A game against the computer in which seat 0 (the guest) goes first, has placed a Pokémon and
  # has drawn the card that starts the turn.
  def started_game
    get games_url # makes this browser a guest
    guest = Player.order(:id).last
    game = Game.start!(decks: [@water, @grass], players: [guest, nil], mode: 'bot', first_player: 0)
    engine = game.engine
    active = engine.player(0)['hand'].find { |uid| engine.card(uid).basic_pokemon? }
    play(game, 'type' => 'setup', 'active' => active)
    play(game, 'type' => 'draw')
    game.reload
  end

  def play(game, action)
    post actions_game_url(game), params: action.merge('version' => game.reload.version)
  end

  # Puts a card into a seat's hand and returns its uid.
  def put_in_hand(game, seat, card)
    engine = game.reload.engine
    engine.catalog[card.id] = card
    engine.state['cards'] << card.id
    uid = engine.state['cards'].size - 1
    engine.player(seat)['hand'] << uid
    game.update!(state: engine.state)
    uid
  end

  def nothing_trainer(subtype = 'item')
    make_trainer('Plain', subtype, { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => 'Fire', 'amount' => 0, 'turns' => 0 })
  end

  test "a Trainer card in the hand has a play button" do
    game = started_game
    uid = put_in_hand(game, 0, nothing_trainer)

    get game_url(game)

    assert_select ".hand-card form input[name=card][value='#{uid}']"
    assert_select '.hand-card .choice', 0
  end

  test "playing a Trainer card through the page" do
    game = started_game
    uid = put_in_hand(game, 0, nothing_trainer)

    play(game, 'type' => 'play', 'card' => uid)

    assert_nil flash[:danger]
    assert_includes game.reload.engine.player(0)['discard'], uid
  end

  test "a Trainer card with a choice shows a form and takes the choice" do
    game = started_game
    uid = put_in_hand(game, 0, make_trainer('Heal', 'item', { 'op' => 'heal', 'amount' => 30 }))
    engine = game.reload.engine
    engine.active(0)['damage'] = 20
    game.update!(state: engine.state)

    get game_url(game)
    assert_select '.hand-card details.choice select[name=target] option', 1

    play(game, 'type' => 'play', 'card' => uid, 'target' => 'active')

    assert_nil flash[:danger]
    assert_equal 0, game.reload.engine.active(0)['damage']
  end

  test "a choice that isn't allowed is refused with the reason" do
    game = started_game
    uid = put_in_hand(game, 0, make_trainer('Heal', 'item', { 'op' => 'heal', 'amount' => 30 }))

    play(game, 'type' => 'play', 'card' => uid, 'target' => 'bench-4')

    assert_match(/Nothing to choose|Choose a value/, flash[:danger])
  end

  test "searching the deck shows the list and takes the choice" do
    game = started_game
    ball = make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'energy' }] })
    uid = put_in_hand(game, 0, ball)

    play(game, 'type' => 'play', 'card' => uid)
    get game_url(game)

    assert_select '.search-panel'
    assert_select '.search-card input[type=checkbox]:not([disabled])'
    energy = game.reload.engine.pending['source'].find { |card| game.engine.card(card).energy? }

    play(game, 'type' => 'choose', 'cards' => [energy])

    assert_nil flash[:danger]
    assert_includes game.reload.engine.player(0)['hand'], energy
    assert_nil game.engine.pending
  end

  test "a search can't take cards that don't fit" do
    game = started_game
    ball = make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'energy' }] })
    play(game, 'type' => 'play', 'card' => put_in_hand(game, 0, ball))
    pokemon = game.reload.engine.pending['source'].find { |card| game.engine.card(card).pokemon? }

    play(game, 'type' => 'choose', 'cards' => [pokemon])

    assert_match(/don't fit/, flash[:danger])
    assert_equal 'search', game.reload.engine.pending['type']
  end

  test "using an Ability through the page" do
    game = started_game
    ability = { 'name' => 'Errand', 'kind' => 'Ability', 'trigger' => 'activated', 'needs' => {}, 'effects' => [{ 'op' => 'draw', 'count' => 2 }], 'supported' => true }
    drawer = make_card(name: 'Drawer', hp: 100, attacks: [attack], abilities: [ability])
    engine = game.reload.engine
    engine.catalog[drawer.id] = drawer
    engine.state['cards'] << drawer.id
    engine.active(0)['stack'] = [engine.state['cards'].size - 1]
    game.update!(state: engine.state)
    hand = engine.player(0)['hand'].size

    get game_url(game)
    assert_select 'form input[name=type][value=ability]'

    play(game, 'type' => 'ability', 'slot' => 'active', 'index' => 0)

    assert_nil flash[:danger]
    assert_equal hand + 2, game.reload.engine.player(0)['hand'].size
  end

  test "Special Conditions show on the Pokémon" do
    game = started_game
    engine = game.reload.engine
    engine.active(1)['conditions'] = ['poisoned']
    game.update!(state: engine.state)

    get game_url(game)

    assert_select '.mat--theirs .condition--poisoned', 'Poisoned'
  end

  test "a Stadium is shown above the table" do
    game = started_game
    uid = put_in_hand(game, 0, make_trainer('Garden', 'stadium', { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => 'Fire', 'amount' => 10 }))

    play(game, 'type' => 'play', 'card' => uid)
    get game_url(game)

    assert_select '.stadium-banner', /Garden/
  end

  test "an effect that makes the opponent switch is answered by the computer by itself" do
    game = started_game
    uid = put_in_hand(game, 0, make_trainer('Repel', 'item', { 'op' => 'switch_opponent' }))
    engine = game.reload.engine
    basic = put_in_hand(game, 1, cards(:sprigling))
    engine = game.reload.engine
    engine.player(1)['hand'].delete(basic)
    engine.bench(1) << { 'stack' => [basic], 'energy' => [], 'damage' => 0, 'since' => 0, 'conditions' => [] }
    game.update!(state: engine.state)

    play(game, 'type' => 'play', 'card' => uid)

    assert_nil flash[:danger]
    assert_nil game.reload.engine.pending
    assert_equal 0, game.engine.seat_to_act
  end
end
