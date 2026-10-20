require "test_helper"

class Tcg::EngineAbilitiesTest < ActiveSupport::TestCase
  def ability(name, trigger, *effects, **needs)
    { 'name' => name, 'kind' => 'Ability', 'trigger' => trigger, 'needs' => needs.stringify_keys, 'effects' => effects, 'supported' => true }
  end

  def passive(kind, **fields)
    ability("Passive #{kind}", 'passive', { 'op' => 'passive', 'kind' => kind }.merge(fields.stringify_keys))
  end

  # Seat 0 is to move in turn 3 with +mine+ as its Active Pokémon.
  def play_with(mine, theirs = nil)
    engine = start_play(first_player: 0)
    put_in_play(engine, 0, mine, where: :active)
    put_in_play(engine, 1, theirs, where: :active) if theirs
    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')
    engine
  end

  def hitter(damage, **options)
    make_card(name: 'Hitter', hp: 200, attacks: [attack(cost: [], damage: damage)], **options)
  end

  # ---------------------------------------------------------------- passive

  test "a Pokémon that takes less damage from attacks" do
    tough = make_card(name: 'Tough', hp: 200, attacks: [attack], abilities: [passive('reduce_incoming', amount: 30)])
    engine = play_with(hitter(60), tough)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 30, engine.active(1)['damage']
  end

  test "less damage only from Pokémon of some types" do
    tough = make_card(name: 'Tough', hp: 200, attacks: [attack], abilities: [passive('reduce_incoming', amount: 30, types: %w[Fire Water])])
    engine = play_with(hitter(60), tough)
    engine.perform(0, 'type' => 'attack', 'index' => 0)
    assert_equal 60, engine.active(1)['damage'] # a Colorless attacker

    engine = play_with(make_card(name: 'Burner', hp: 200, type: 'Fire', attacks: [attack(cost: [], damage: 60)]), tough)
    engine.perform(0, 'type' => 'attack', 'index' => 0)
    assert_equal 30, engine.active(1)['damage']
  end

  test "an Ability that makes your Pokémon of a type do more damage, from anywhere in play" do
    booster = make_card(name: 'Booster', hp: 100, attacks: [attack], abilities: [passive('plus_damage', type: 'Colorless', amount: 20)])
    engine = play_with(hitter(30))
    put_in_play(engine, 0, booster)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 50, engine.active(1)['damage']
  end

  test "an Ability that stops the effects of attacks but not the damage" do
    safe = make_card(name: 'Safe', hp: 200, attacks: [attack], abilities: [passive('protect_effects')])
    attacker = make_card(name: 'Venom', hp: 200, attacks: [attack(cost: [], damage: 10, effects: [{ 'op' => 'inflict', 'condition' => 'poisoned' }])])
    engine = play_with(attacker, safe)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 10 , engine.active(1)['damage']
    assert_empty engine.active(1)['conditions']
  end

  test "an Active Pokémon whose Ability weakens the opponent's attacks" do
    wall = make_card(name: 'Wall', hp: 200, attacks: [attack], abilities: [passive('reduce_opponent_damage', amount: 20)])
    engine = play_with(hitter(50), wall)

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 30, engine.active(1)['damage']
  end

  test "a Pokémon with no Energy attached has no Retreat Cost" do
    light = make_card(name: 'Light', hp: 100, attacks: [attack], retreat_cost: 3, abilities: [passive('free_retreat_without_energy')])
    engine = play_with(light)
    put_in_play(engine, 0, :sprigling)

    assert_equal 0, engine.retreat_cost(0)
    assert_nil engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => [])
  end

  # ---------------------------------------------------------------- used once during the turn

  test "an Ability used once during the turn" do
    drawer = make_card(name: 'Drawer', hp: 100, attacks: [attack], abilities: [ability('Run Errand', 'activated', { 'op' => 'draw', 'count' => 2 }, active: true)])
    engine = play_with(drawer)
    hand = engine.player(0)['hand'].size

    engine.perform(0, 'type' => 'ability', 'slot' => 'active', 'index' => 0)

    assert_equal hand + 2, engine.player(0)['hand'].size
    assert_match(/already used Run Errand/, engine.error_for(0, 'type' => 'ability', 'slot' => 'active', 'index' => 0))

    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')
    assert_nil engine.error_for(0, 'type' => 'ability', 'slot' => 'active', 'index' => 0)
  end

  test "an Ability that needs the Pokémon to be Active can't be used from the Bench" do
    drawer = make_card(name: 'Drawer', hp: 100, attacks: [attack], abilities: [ability('Run Errand', 'activated', { 'op' => 'draw', 'count' => 2 }, active: true)])
    engine = play_with(hitter(10))
    put_in_play(engine, 0, drawer)

    assert_match(/Active Spot/, engine.error_for(0, 'type' => 'ability', 'slot' => 'bench-0', 'index' => 0))
  end

  test "an Ability that needs Energy of a type on the Pokémon" do
    healer = make_card(name: 'Healer', hp: 100, attacks: [attack], abilities: [ability('Mend', 'activated', { 'op' => 'heal', 'amount' => 30 }, energy_type: 'Grass')])
    engine = play_with(healer)
    engine.active(0)['damage'] = 50
    action = { 'type' => 'ability', 'slot' => 'active', 'index' => 0, 'target' => 'active' }

    assert_match(/needs Grass Energy/, engine.error_for(0, action))

    energy = give(engine, 0, :grass_energy, zone: 'discard')
    engine.player(0)['discard'].delete(energy)
    engine.active(0)['energy'] << energy
    engine.perform(0, action)

    assert_equal 20, engine.active(0)['damage']
  end

  test "an Ability with a choice lists its options among the legal actions" do
    healer = make_card(name: 'Healer', hp: 100, attacks: [attack], abilities: [ability('Mend', 'activated', { 'op' => 'heal', 'amount' => 30 })])
    engine = play_with(healer)
    put_in_play(engine, 0, :sprigling, damage: 10)

    actions = engine.legal_actions(0).select { |action| action['type'] == 'ability' }

    assert_equal [{ 'type' => 'ability', 'slot' => 'active', 'index' => 0, 'target' => 'bench-0' }], actions
  end

  # ---------------------------------------------------------------- when evolving

  test "an Ability that works when the Pokémon evolves" do
    smart = make_card(name: 'Smartling', hp: 100, subtype: 'stage1', evolves_from: 'Sprigling', attacks: [attack],
                      abilities: [ability('Quick Study', 'on_evolve', { 'op' => 'draw', 'count' => 2 })])
    engine = start_play(first_player: 0)
    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')
    uid = give(engine, 0, smart)
    hand = engine.player(0)['hand'].size

    engine.perform(0, 'type' => 'evolve', 'card' => uid, 'target' => 'active')

    assert_equal hand - 1 + 2, engine.player(0)['hand'].size
  end

  test "an evolving Ability can confuse the opponent's Active Pokémon" do
    smart = make_card(name: 'Daze', hp: 100, subtype: 'stage1', evolves_from: 'Sprigling', attacks: [attack],
                      abilities: [ability('Daze Them', 'on_evolve', { 'op' => 'inflict', 'condition' => 'confused' })])
    engine = start_play(first_player: 0)
    engine.perform(0, 'type' => 'end_turn')
    engine.perform(1, 'type' => 'end_turn')

    engine.perform(0, 'type' => 'evolve', 'card' => give(engine, 0, smart), 'target' => 'active')

    assert_equal ['confused'], engine.active(1)['conditions']
  end
end
