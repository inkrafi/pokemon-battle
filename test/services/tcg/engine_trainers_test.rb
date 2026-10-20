require "test_helper"

class Tcg::EngineTrainersTest < ActiveSupport::TestCase
  # Seat 0 is to move in turn 3: both players have had a turn, so first-turn rules are over.
  def play_state
    engine = start_play(first_player: 0)
    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')
    engine
  end

  def play!(engine, uid, extra = {})
    engine.perform(0, { 'type' => 'play', 'card' => uid }.merge(extra))
  end

  def error(engine, uid, extra = {})
    engine.error_for(0, { 'type' => 'play', 'card' => uid }.merge(extra))
  end

  # A card in the deck, at the top, for searches.
  def stack_deck(engine, seat, card)
    uid = give(engine, seat, card, zone: 'deck')
    engine.player(seat)['deck'].delete(uid)
    engine.player(seat)['deck'].unshift(uid)
    uid
  end

  def energize(engine, slot, fixture, count = 1)
    count.times { slot['energy'] << give(engine, 0, fixture, zone: 'discard').tap { |uid| engine.player(0)['discard'].delete(uid) } }
  end

  # ---------------------------------------------------------------- rules for playing

  test "only Trainer cards in the hand can be played" do
    engine = play_state

    assert_match(/not in your hand/, error(engine, 9999))
    assert_match(/Only a Trainer/, error(engine, engine.player(0)['hand'].first)) if engine.card(engine.player(0)['hand'].first).pokemon?
  end

  test "an Item goes to the discard pile after it is used and there is no limit" do
    draw2 = make_trainer('Nothing Much', 'item', { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => 'Fire', 'amount' => 0, 'turns' => 0 })
    engine = play_state
    first = give(engine, 0, draw2)
    second = give(engine, 0, draw2)

    play!(engine, first)
    play!(engine, second)

    assert_includes engine.player(0)['discard'], first
    assert_includes engine.player(0)['discard'], second
  end

  test "a Supporter can be played once per turn, and not by the player who goes first on turn one" do
    boss = make_trainer('Order', 'supporter', { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => 'Fire', 'amount' => 0, 'turns' => 0 })
    first_turn = start_play(first_player: 0)
    uid = give(first_turn, 0, boss)
    assert_match(/goes first can't play a Supporter/, error(first_turn, uid))

    engine = play_state
    one = give(engine, 0, boss)
    two = give(engine, 0, boss)
    play!(engine, one)
    assert_match(/already played a Supporter/, error(engine, two))

    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')
    assert_nil error(engine, two)
  end

  test "the second player may play a Supporter in their first turn" do
    boss = make_trainer('Order', 'supporter', { 'op' => 'shuffle_hand_draw', 'count' => 1, 'if_prizes' => 0, 'else_count' => 1 })
    engine = start_play(first_player: 1)
    engine.perform(1, 'type' => 'end_turn')
    uid = give(engine, 0, boss)

    assert_nil error(engine, uid)
  end

  test "Lillie's way of drawing depends on the Prize cards left" do
    shuffle = make_trainer('Fresh Hand', 'supporter', { 'op' => 'shuffle_hand_draw', 'count' => 6, 'if_prizes' => 6, 'else_count' => 8 })
    engine = play_state
    uid = give(engine, 0, shuffle)

    play!(engine, uid)

    assert_equal 8, engine.player(0)['hand'].size # six Prize cards left: the bigger draw
  end

  test "an Item that needs cards to discard says so" do
    ball = make_trainer('Ball', 'item', { 'op' => 'discard_from_hand', 'count' => 2 }, { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'pokemon' }] })
    engine = play_state
    uid = give(engine, 0, ball)

    assert_match(/Choose 2 cards/, error(engine, uid))
    assert_match(/Choose 2 cards/, error(engine, uid, 'discard' => [engine.player(0)['hand'].first]))

    others = engine.player(0)['hand'].reject { |card| card == uid }.first(2)
    assert_nil error(engine, uid, 'discard' => others)
    assert_match(/Choose 2 cards/, error(engine, uid, 'discard' => [uid, others.first])) # not itself
  end

  # ---------------------------------------------------------------- searching

  test "searching the deck asks the player to choose from the matching cards" do
    ball = make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'pokemon', 'subtype' => 'stage1' }] })
    engine = play_state
    target = stack_deck(engine, 0, :bloomling)
    uid = give(engine, 0, ball)
    total = engine.card_total(0)

    play!(engine, uid)

    assert_equal 'search', engine.pending['type']
    assert_match(/Finish your search/, engine.error_for(0, 'type' => 'end_turn'))
    assert_match(/searching their deck/, engine.error_for(1, 'type' => 'end_turn'))
    assert_match(/don't fit/, engine.error_for(0, 'type' => 'choose', 'cards' => [engine.player(0)['deck'].last]))

    engine.perform(0, 'type' => 'choose', 'cards' => [target])

    assert_nil engine.pending
    assert_includes engine.player(0)['hand'], target
    assert_equal total, engine.card_total(0)
  end

  test "a search may find nothing" do
    ball = make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'pokemon' }] })
    engine = play_state
    uid = give(engine, 0, ball)
    hand = engine.player(0)['hand'].size

    play!(engine, uid)
    engine.perform(0, 'type' => 'choose', 'cards' => [])

    assert_equal hand - 1, engine.player(0)['hand'].size
    assert_nil engine.pending
  end

  test "up to two Basic Pokémon go straight onto the Bench" do
    poffin = make_trainer('Poffin', 'item', { 'op' => 'search', 'to' => 'bench', 'filters' => [{ 'supertype' => 'pokemon', 'subtype' => 'basic', 'max_hp' => 70 }] * 2 })
    engine = play_state
    uid = give(engine, 0, poffin)
    picks = 2.times.map { stack_deck(engine, 0, :sprigling) }
    total = engine.card_total(0)

    play!(engine, uid)
    engine.perform(0, 'type' => 'choose', 'cards' => picks)

    assert_equal 2, engine.bench(0).size
    assert_equal total, engine.card_total(0)
  end

  test "searching for the Bench can't be played with a full Bench" do
    poffin = make_trainer('Poffin', 'item', { 'op' => 'search', 'to' => 'bench', 'filters' => [{ 'supertype' => 'pokemon', 'subtype' => 'basic' }] })
    engine = play_state
    5.times { put_in_play(engine, 0, :sprigling) }
    uid = give(engine, 0, poffin)

    assert_match(/no room on your Bench/, error(engine, uid))
  end

  test "looking at the top cards puts the others back at the bottom" do
    move = make_trainer('Move', 'supporter', { 'op' => 'search', 'top' => 3, 'to' => 'bench', 'rest' => 'bottom', 'filters' => [{ 'supertype' => 'pokemon', 'type' => 'Grass' }] })
    engine = play_state
    uid = give(engine, 0, move)
    pick = stack_deck(engine, 0, :sprigling)
    deck_size = engine.player(0)['deck'].size

    play!(engine, uid)
    assert_equal [pick], engine.pending['source'].select { |card| engine.card(card).pokemon? && engine.card(card).type == 'Grass' && card == pick }
    engine.perform(0, 'type' => 'choose', 'cards' => [pick])

    assert_equal deck_size - 1, engine.player(0)['deck'].size
    assert_equal 'Sprigling', engine.top_card(engine.bench(0).last).name
  end

  # ---------------------------------------------------------------- switching

  test "switching your own Pokémon" do
    switch = make_trainer('Switch', 'item', { 'op' => 'switch_own' })
    engine = play_state
    put_in_play(engine, 0, :bloomling)
    uid = give(engine, 0, switch)

    assert_match(/Choose a value/, error(engine, uid))
    play!(engine, uid, 'to' => 0)

    assert_equal 'Bloomling', engine.top_card(engine.active(0)).name
    assert_equal 'Sprigling', engine.top_card(engine.bench(0).first).name
  end

  test "a Trainer that pulls a Pokémon of the opponent into the Active Spot" do
    gust = make_trainer('Gust', 'supporter', { 'op' => 'gust' })
    engine = play_state
    put_in_play(engine, 1, :bloomling)
    uid = give(engine, 0, gust)

    play!(engine, uid, 'opp' => 0)

    assert_equal 'Bloomling', engine.top_card(engine.active(1)).name
  end

  test "a Trainer that switches out the opponent's Active Pokémon lets them choose" do
    repel = make_trainer('Repel', 'item', { 'op' => 'switch_opponent' })
    engine = play_state
    put_in_play(engine, 1, :bloomling)
    uid = give(engine, 0, repel)

    play!(engine, uid)
    assert_equal 1, engine.pending['seat']
    engine.perform(1, 'type' => 'switch', 'index' => 0)

    assert_equal 'Bloomling', engine.top_card(engine.active(1)).name
    assert_equal 0, engine.current # the turn goes on
    assert_nil engine.pending
  end

  # ---------------------------------------------------------------- Energy, healing, discard

  test "moving a Basic Energy between your Pokémon" do
    move = make_trainer('Energy Switch', 'item', { 'op' => 'move_energy' })
    engine = play_state
    bench = put_in_play(engine, 0, :sprigling)
    energize(engine, engine.active(0), :grass_energy)
    energy = engine.active(0)['energy'].first
    uid = give(engine, 0, move)

    assert_match(/different Pokémon/, error(engine, uid, 'energy' => energy, 'to_target' => 'active'))
    play!(engine, uid, 'energy' => energy, 'to_target' => 'bench-0')

    assert_empty engine.active(0)['energy']
    assert_equal [energy], bench['energy']
  end

  test "taking a card back from the discard pile" do
    stretcher = make_trainer('Stretcher', 'item', { 'op' => 'recover', 'filter' => { 'any' => [{ 'supertype' => 'pokemon' }, { 'supertype' => 'energy', 'basic_energy' => true }] } })
    engine = play_state
    lost = give(engine, 0, :bloomling, zone: 'discard')
    uid = give(engine, 0, stretcher)

    play!(engine, uid, 'pick' => lost)

    assert_includes engine.player(0)['hand'], lost
    assert_not_includes engine.player(0)['discard'], lost
  end

  test "healing a Pokémon and curing its Conditions" do
    lady = make_trainer('Healer', 'supporter', { 'op' => 'heal', 'amount' => 60, 'cure' => true })
    engine = play_state
    engine.active(0)['damage'] = 40
    engine.send(:inflict, engine.active(0), 'poisoned')
    uid = give(engine, 0, lady)

    play!(engine, uid, 'target' => 'active')

    assert_equal 0, engine.active(0)['damage']
    assert_empty engine.active(0)['conditions']
  end

  test "healing only offers damaged Pokémon" do
    lady = make_trainer('Healer', 'supporter', { 'op' => 'heal', 'amount' => 60 })
    engine = play_state
    uid = give(engine, 0, lady)

    assert_match(/Nothing to choose/, error(engine, uid))
  end

  test "healing everything from a Mega ex returns its Energy" do
    mega = make_card(name: 'Mega Bigmon ex', hp: 300, prize_value: 3, attacks: [attack])
    engine = play_state
    slot = put_in_play(engine, 0, mega, where: :active)
    slot['damage'] = 120
    energize(engine, slot, :fire_energy, 2)
    heal = make_trainer('Care', 'supporter', { 'op' => 'heal', 'amount' => 'all', 'mega_only' => true, 'return_energy' => true })
    uid = give(engine, 0, heal)
    hand = engine.player(0)['hand'].size

    play!(engine, uid, 'target' => 'active')

    assert_equal 0, slot['damage']
    assert_empty slot['energy']
    assert_equal hand - 1 + 2, engine.player(0)['hand'].size
  end

  test "attaching an Energy card from the discard pile to a Benched Pokémon of the type" do
    patch = make_trainer('Patch', 'item', { 'op' => 'attach_from_discard', 'type' => 'Grass' })
    engine = play_state
    bench = put_in_play(engine, 0, :sprigling)
    energy = give(engine, 0, :grass_energy, zone: 'discard')
    uid = give(engine, 0, patch)

    play!(engine, uid, 'pick' => energy, 'target' => 'bench-0')

    assert_equal [energy], bench['energy']
    assert_not engine.player(0)['flags']['energy'] # it isn't the Energy for the turn
  end

  # ---------------------------------------------------------------- lasting effects

  test "Pokémon of one type do more damage for the rest of the turn" do
    power = make_trainer('Power', 'item', { 'op' => 'player_mark', 'kind' => 'plus_damage', 'type' => 'Colorless', 'amount' => 30, 'turns' => 0 })
    brawler = make_card(name: 'Brawler', hp: 100, attacks: [attack(cost: [], damage: 20)])
    engine = play_state
    put_in_play(engine, 0, brawler, where: :active)
    uid = give(engine, 0, power)

    play!(engine, uid)
    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 50, engine.active(1)['damage']
  end

  test "a Trainer that lowers damage for your Pokémon of a type, also those that come later" do
    shield = make_trainer('Shield', 'item', { 'op' => 'player_mark', 'kind' => 'reduce_incoming', 'type' => 'Grass', 'amount' => 30, 'turns' => 1 })
    engine = play_state
    put_in_play(engine, 1, make_card(name: 'Hitter', hp: 100, attacks: [attack(cost: [], damage: 50)]), where: :active)
    uid = give(engine, 0, shield)
    play!(engine, uid)
    engine.perform(0, 'type' => 'end_turn')

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 20, engine.active(0)['damage']
  end

  test "a Pokémon can be protected from Pokémon ex for a turn" do
    charm = make_trainer('Mischief', 'supporter', { 'op' => 'protect_own', 'from' => 'ex' })
    engine = play_state
    put_in_play(engine, 1, make_card(name: 'Bully ex', hp: 200, prize_value: 2, attacks: [attack(cost: [], damage: 50)]), where: :active)
    uid = give(engine, 0, charm)
    play!(engine, uid, 'target' => 'active')
    engine.perform(0, 'type' => 'end_turn')

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 0, engine.active(0)['damage']
  end

  test "a Trainer with a limit on the opponent's Prize cards" do
    mischief = make_trainer('Late Game', 'supporter', { 'op' => 'require_opponent_prizes_at_most', 'count' => 2 }, { 'op' => 'shuffle_hand_draw', 'count' => 1, 'if_prizes' => 0, 'else_count' => 1 })
    engine = play_state
    uid = give(engine, 0, mischief)
    assert_match(/2 or fewer Prize cards/, error(engine, uid))

    engine.player(1)['prizes'].pop(4)
    assert_nil error(engine, uid)
  end

  # ---------------------------------------------------------------- Rare Candy

  test "Rare Candy evolves a Basic Pokémon straight into a Stage 2" do
    candy = make_trainer('Candy', 'item', { 'op' => 'rare_candy' })
    engine = play_state
    stage2 = give(engine, 0, :thornlord)
    uid = give(engine, 0, candy)

    play!(engine, uid, 'target' => 'active', 'with' => stage2)

    assert_equal 'Thornlord', engine.top_card(engine.active(0)).name
    assert_equal 2, engine.active(0)['stack'].size
  end

  test "Rare Candy can't be used on a Pokémon that was just played" do
    candy = make_trainer('Candy', 'item', { 'op' => 'rare_candy' })
    engine = play_state
    put_in_play(engine, 0, :sprigling, where: :active, since: engine.turn_number)
    give(engine, 0, :thornlord)
    uid = give(engine, 0, candy)

    assert_match(/Nothing to choose/, error(engine, uid))
  end

  # ---------------------------------------------------------------- Tools

  test "a Pokémon Tool is attached to a Pokémon without one and stays until it leaves play" do
    helmet = make_trainer('Helmet', 'tool', { 'op' => 'tool', 'kind' => 'retaliate', 'type' => 'Colorless', 'amount' => 40 })
    engine = play_state
    uid = give(engine, 0, helmet)

    play!(engine, uid, 'target' => 'active')

    assert_equal uid, engine.active(0)['tool']
    assert_not_includes engine.player(0)['discard'], uid
    second = give(engine, 0, helmet)
    assert_match(/Nothing to choose/, error(engine, second))
  end

  test "a Tool that lowers the Retreat Cost" do
    balloon = make_trainer('Balloon', 'tool', { 'op' => 'tool', 'kind' => 'retreat_less', 'amount' => 2 })
    engine = play_state
    put_in_play(engine, 0, :sprigling)
    play!(engine, give(engine, 0, balloon), 'target' => 'active')

    assert_equal 0, engine.retreat_cost(0)
    assert_nil engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => [])
  end

  test "a Tool that hits back puts damage on the attacker, even after its Pokémon was Knocked Out" do
    helmet = make_trainer('Helmet', 'tool', { 'op' => 'tool', 'kind' => 'retaliate', 'type' => 'Colorless', 'amount' => 40 })
    tank = make_card(name: 'Tank', hp: 30, attacks: [attack(cost: [], damage: 10)])
    engine = play_state
    put_in_play(engine, 0, :sprigling)
    put_in_play(engine, 0, tank, where: :active)
    put_in_play(engine, 1, make_card(name: 'Hitter', hp: 100, attacks: [attack(cost: [], damage: 50)]), where: :active)
    engine.player(0)['active']['tool'] = give(engine, 0, helmet, zone: 'discard').tap { |tool| engine.player(0)['discard'].delete(tool) }
    engine.perform(0, 'type' => 'end_turn')

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 40, engine.active(1)['damage']
    assert_equal 5, engine.player(1)['prizes'].size # the Prize was taken
  end

  test "a Tool that lowers damage from Pokémon with an Ability" do
    charm = make_trainer('Charm', 'tool', { 'op' => 'tool', 'kind' => 'reduce_from_ability', 'amount' => 30 })
    engine = play_state
    hitter = make_card(name: 'Talker', hp: 100, attacks: [attack(cost: [], damage: 50)], abilities: [{ 'name' => 'Chat', 'kind' => 'Ability' }])
    put_in_play(engine, 1, hitter, where: :active)
    play!(engine, give(engine, 0, charm), 'target' => 'active')
    engine.perform(0, 'type' => 'end_turn')

    engine.perform(1, 'type' => 'attack', 'index' => 0)

    assert_equal 20, engine.active(0)['damage']
  end

  # ---------------------------------------------------------------- Stadiums

  test "a Stadium stays in play until another replaces it" do
    garden = make_trainer('Garden', 'stadium', { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => 'Darkness', 'amount' => 20 })
    other = make_trainer('Other Place', 'stadium', { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => 'Darkness', 'amount' => 10 })
    engine = play_state
    first = give(engine, 0, garden)
    play!(engine, first)

    assert_equal first, engine.state['stadium']['uid']
    assert_match(/already played a Stadium/, error(engine, give(engine, 0, other)))
    assert_match(/Garden is already in play/, (engine.perform(0, 'type' => 'end_turn'); engine.perform(1, 'type' => 'end_turn'); error(engine, give(engine, 0, garden))))

    play!(engine, give(engine, 0, other))
    assert_includes engine.player(0)['discard'], first
  end

  test "a Stadium that damages Basic Pokémon put on the Bench" do
    ruins = make_trainer('Ruins', 'stadium', { 'op' => 'stadium', 'kind' => 'bench_damage', 'except_type' => 'Darkness', 'amount' => 20 })
    engine = play_state
    play!(engine, give(engine, 0, ruins))
    basic = give(engine, 0, :sprigling)

    engine.perform(0, 'type' => 'bench', 'card' => basic)

    assert_equal 20, engine.bench(0).last['damage']
  end

  test "a Stadium that lets Pokémon evolve in the turn they were played" do
    forest = make_trainer('Forest', 'stadium', { 'op' => 'stadium', 'kind' => 'evolve_at_once', 'type' => 'Grass' })
    engine = play_state
    play!(engine, give(engine, 0, forest))
    basic = give(engine, 0, :sprigling)
    engine.perform(0, 'type' => 'bench', 'card' => basic)
    evolution = give(engine, 0, :bloomling)

    assert_nil engine.error_for(0, 'type' => 'evolve', 'card' => evolution, 'target' => 'bench-0')
    engine.perform(0, 'type' => 'evolve', 'card' => evolution, 'target' => 'bench-0')

    again = give(engine, 0, :thornlord)
    assert_match(/in the turn it was played or evolved/, engine.error_for(0, 'type' => 'evolve', 'card' => again, 'target' => 'bench-0'))
  end

  # ---------------------------------------------------------------- listing

  test "the Trainers that can be played are among the legal actions" do
    switch = make_trainer('Switch', 'item', { 'op' => 'switch_own' })
    engine = play_state
    put_in_play(engine, 0, :bloomling)
    uid = give(engine, 0, switch)

    plays = engine.legal_actions(0).select { |action| action['type'] == 'play' }

    assert_equal [{ 'type' => 'play', 'card' => uid, 'to' => 0 }], plays
  end

  test "a Trainer with nothing to choose from isn't offered" do
    heal = make_trainer('Healer', 'supporter', { 'op' => 'heal', 'amount' => 30 })
    engine = play_state
    give(engine, 0, heal)

    assert_empty engine.legal_actions(0).select { |action| action['type'] == 'play' }
  end

  test "the computer's search options pick what matches" do
    ball = make_trainer('Ball', 'item', { 'op' => 'search', 'to' => 'hand', 'filters' => [{ 'supertype' => 'pokemon', 'subtype' => 'stage1' }] })
    engine = play_state
    target = stack_deck(engine, 0, :bloomling)
    play!(engine, give(engine, 0, ball))

    options = engine.legal_actions(0).select { |action| action['type'] == 'choose' }

    assert_includes options, { 'type' => 'choose', 'cards' => [target] }
    assert_includes options, { 'type' => 'choose', 'cards' => [] }
  end
end
