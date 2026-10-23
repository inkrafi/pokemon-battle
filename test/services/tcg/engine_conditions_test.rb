require "test_helper"

class Tcg::EngineConditionsTest < ActiveSupport::TestCase
  # Seat 0 is to move in turn 2 with a Pokémon that has plenty of HP on both sides.
  def setup_play
    tank = make_card(name: 'Tank', hp: 200, attacks: [attack(cost: [], damage: 10)])
    engine = start_play(first_player: 1)
    put_in_play(engine, 0, tank, where: :active)
    put_in_play(engine, 1, tank, where: :active)
    end_turn(engine)
    engine
  end

  def inflict(engine, seat, *names)
    names.each { |name| engine.send(:inflict, engine.active(seat), name) }
  end

  # An engine whose coin always lands the same way.
  def rigged(engine, heads:)
    rng = Object.new
    rng.define_singleton_method(:rand) { |*| heads ? 1 : 0 }
    engine.instance_variable_set(:@rng, rng)
  end

  test "Poisoned and Burned take 10 damage each in the Checkup" do
    engine = setup_play
    rigged(engine, heads: false)
    inflict(engine, 1, 'poisoned', 'burned')

    end_turn(engine)

    assert_equal 20, engine.active(1)['damage']
    assert_equal ['poisoned', 'burned'], engine.active(1)['conditions']
  end

  test "the Checkup also hits the Pokémon of the player whose turn just ended" do
    engine = setup_play
    inflict(engine, 0, 'poisoned')

    end_turn(engine)

    assert_equal 10, engine.active(0)['damage']
  end

  test "Burn goes away on heads, Sleep too" do
    engine = setup_play
    rigged(engine, heads: true)
    inflict(engine, 1, 'burned', 'asleep')

    end_turn(engine)

    assert_empty engine.active(1)['conditions']
  end

  test "Sleep and Burn stay on tails" do
    engine = setup_play
    rigged(engine, heads: false)
    inflict(engine, 1, 'burned', 'asleep')

    end_turn(engine)

    assert_equal %w[burned asleep], engine.active(1)['conditions']
  end

  test "Paralysis wears off after the owner's own next turn, not before" do
    engine = setup_play
    inflict(engine, 1, 'paralyzed')

    end_turn(engine) # the Checkup after the attacker's turn
    assert_equal ['paralyzed'], engine.active(1)['conditions']

    end_turn(engine)
    assert_empty engine.active(1)['conditions']
  end

  test "a new one of Asleep, Confused, Paralyzed replaces the old one but Poison stays" do
    engine = setup_play
    inflict(engine, 1, 'poisoned', 'asleep', 'confused')

    assert_equal %w[poisoned confused], engine.active(1)['conditions']
  end

  test "an Asleep or Paralyzed Pokémon can't attack or retreat" do
    engine = setup_play
    put_in_play(engine, 0, :sprigling)
    inflict(engine, 0, 'asleep')

    assert_match(/Asleep and can't attack/, engine.error_for(0, 'type' => 'attack', 'index' => 0))
    assert_match(/Asleep and can't retreat/, engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => []))

    inflict(engine, 0, 'paralyzed')
    assert_match(/Paralyzed and can't attack/, engine.error_for(0, 'type' => 'attack', 'index' => 0))
  end

  test "a Confused Pokémon can retreat, and retreating cures it" do
    engine = setup_play
    benched = put_in_play(engine, 0, :sprigling)
    energy = give(engine, 0, :grass_energy, zone: 'discard')
    engine.player(0)['discard'].delete(energy)
    engine.active(0)['energy'] << energy
    old_active = engine.active(0)
    inflict(engine, 0, 'confused', 'poisoned')

    engine.perform(0, 'type' => 'retreat', 'to' => 0, 'energy' => [energy])

    assert_empty old_active['conditions']
    assert_equal benched, engine.active(0)
  end

  test "evolving cures every condition" do
    engine = start_play(first_player: 0)
    end_turn(engine)
    end_turn(engine)
    inflict(engine, 0, 'poisoned', 'confused')
    evolution = give(engine, 0, :bloomling)

    engine.perform(0, 'type' => 'evolve', 'card' => evolution, 'target' => 'active')

    assert_empty engine.active(0)['conditions']
  end

  test "a Confused Pokémon that flips tails hurts itself and the attack fails" do
    engine = setup_play
    rigged(engine, heads: false)
    inflict(engine, 0, 'confused')

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 30, engine.active(0)['damage']
    assert_equal 0, engine.active(1)['damage']
    assert_equal 1, engine.current
  end

  test "a Confused Pokémon that flips heads attacks normally" do
    engine = setup_play
    rigged(engine, heads: true)
    inflict(engine, 0, 'confused')

    engine.perform(0, 'type' => 'attack', 'index' => 0)

    assert_equal 10, engine.active(1)['damage']
    assert_equal 0, engine.active(0)['damage']
  end

  test "a Pokémon Knocked Out by Poison gives a Prize and its owner picks a new Active" do
    engine = setup_play
    engine.active(1)['damage'] = 195
    inflict(engine, 1, 'poisoned')
    put_in_play(engine, 1, :sprigling)

    end_turn(engine)

    assert_equal 5, engine.player(0)['prizes'].size
    assert_equal 1, engine.pending['seat']
    assert_equal 'start', engine.pending['stage']

    engine.perform(1, 'type' => 'promote', 'index' => 0)

    assert_equal({ 'type' => 'draw', 'seat' => 1 }, engine.pending) # their turn starts with a draw
    assert_equal 1, engine.current
  end

  test "when the defender is Knocked Out by the attack and the attacker by its Poison, both choose" do
    engine = setup_play
    engine.active(0)['damage'] = 195
    engine.active(1)['damage'] = 190
    inflict(engine, 0, 'poisoned')
    put_in_play(engine, 0, :sprigling)
    put_in_play(engine, 1, :sprigling)

    engine.perform(0, 'type' => 'attack', 'index' => 0) # 10 damage knocks the defender out

    assert_equal 1, engine.pending['seat'] # the defender is replaced first
    engine.perform(1, 'type' => 'promote', 'index' => 0)

    assert_equal 0, engine.pending['seat'] # then the Checkup knocks out the attacker
    assert_equal 'start', engine.pending['stage']
    engine.perform(0, 'type' => 'promote', 'index' => 0)

    assert_equal 1, engine.current
    assert_equal({ 'type' => 'draw', 'seat' => 1 }, engine.pending) # their turn starts with a draw
  end

  test "Poison can knock out the last Pokémon and win the game" do
    engine = setup_play
    engine.active(1)['damage'] = 195
    inflict(engine, 1, 'poisoned')

    end_turn(engine)

    assert engine.finished?
    assert_equal 0, engine.winner
  end
end
