require "test_helper"

class Tcg::EngineTurnTest < ActiveSupport::TestCase
  setup do
    @engine = start_play # seat 0 goes first, both have Sprigling Active
  end

  # ---------------------------------------------------------------- turn order

  test "only the player whose turn it is can act" do
    assert_equal 'It is not your turn.', @engine.error_for(1, 'type' => 'end_turn')
    assert_raises(Tcg::IllegalAction) { @engine.perform(1, 'type' => 'bench', 'card' => give(@engine, 1, :sprigling)) }
  end

  test "ending the turn passes it on and the next player has to draw a card first" do
    before = @engine.player(1)['hand'].size
    deck = @engine.player(1)['deck'].size

    @engine.perform(0, 'type' => 'end_turn')

    assert_equal 1, @engine.current
    assert_equal 2, @engine.turn_number
    assert_equal before, @engine.player(1)['hand'].size
    assert_equal [{ 'type' => 'draw' }, { 'type' => 'concede' }], @engine.legal_actions(1)
    assert_equal 'Draw a card first.', @engine.error_for(1, 'type' => 'end_turn')
    assert_equal 'Your opponent is drawing a card.', @engine.error_for(0, 'type' => 'end_turn')

    @engine.perform(1, 'type' => 'draw')

    assert_equal before + 1, @engine.player(1)['hand'].size
    assert_equal deck - 1, @engine.player(1)['deck'].size
    assert_equal({ 'uid' => @engine.player(1)['hand'].last, 'turn' => 2 }, @engine.player(1)['drawn'])
    assert_nil @engine.pending
    assert_equal 'There is nothing to draw now.', @engine.error_for(1, 'type' => 'draw')
  end

  test "a player who can't draw at the start of their turn loses" do
    @engine.player(1)['deck'].clear

    @engine.perform(0, 'type' => 'end_turn')

    assert @engine.finished?
    assert_equal 0, @engine.winner
    assert_equal 'deck_out', @engine.win_reason
  end

  test "unknown actions and seats are refused" do
    assert_equal 'Unknown action.', @engine.error_for(0, 'type' => 'dance')
    assert_equal 'Unknown seat.', @engine.error_for(2, 'type' => 'end_turn')
  end

  # ---------------------------------------------------------------- bench

  test "a Basic Pokémon goes onto the Bench" do
    uid = uid_of(@engine, 0, :sprigling)

    @engine.perform(0, 'type' => 'bench', 'card' => uid)

    assert_equal [uid], @engine.bench(0).first['stack']
    assert_not_includes @engine.player(0)['hand'], uid
  end

  test "an evolution or Energy can't be benched" do
    assert_match(/Only a Basic Pokémon/, @engine.error_for(0, 'type' => 'bench', 'card' => uid_of(@engine, 0, :bloomling)))
    assert_match(/Only a Basic Pokémon/, @engine.error_for(0, 'type' => 'bench', 'card' => give(@engine, 0, :fire_energy)))
  end

  test "a sixth Pokémon doesn't fit on the Bench" do
    5.times { @engine.perform(0, 'type' => 'bench', 'card' => give(@engine, 0, :sprigling)) }

    assert_match(/Bench is full/, @engine.error_for(0, 'type' => 'bench', 'card' => give(@engine, 0, :sprigling)))
  end

  # ---------------------------------------------------------------- energy

  test "one Energy can be attached per turn" do
    first = give(@engine, 0, :grass_energy)
    second = give(@engine, 0, :grass_energy)

    @engine.perform(0, 'type' => 'attach', 'card' => first, 'target' => 'active')

    assert_equal [first], @engine.active(0)['energy']
    assert_match(/already attached/, @engine.error_for(0, 'type' => 'attach', 'card' => second, 'target' => 'active'))
  end

  test "Energy can go on a Benched Pokémon" do
    @engine.perform(0, 'type' => 'bench', 'card' => uid_of(@engine, 0, :sprigling))
    energy = give(@engine, 0, :grass_energy)

    @engine.perform(0, 'type' => 'attach', 'card' => energy, 'target' => 'bench-0')

    assert_equal [energy], @engine.bench(0).first['energy']
  end

  test "only Energy can be attached, to a Pokémon in play" do
    assert_match(/Only an Energy card/, @engine.error_for(0, 'type' => 'attach', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'active'))
    energy = give(@engine, 0, :grass_energy)
    assert_match(/Choose one of your Pokémon/, @engine.error_for(0, 'type' => 'attach', 'card' => energy, 'target' => 'bench-3'))
    assert_match(/Choose one of your Pokémon/, @engine.error_for(0, 'type' => 'attach', 'card' => energy, 'target' => 'nowhere'))
  end

  test "the Energy allowance comes back next turn" do
    @engine.perform(0, 'type' => 'attach', 'card' => give(@engine, 0, :grass_energy), 'target' => 'active')
    pass_turns(@engine, 2)

    assert_nil @engine.error_for(0, 'type' => 'attach', 'card' => give(@engine, 0, :grass_energy), 'target' => 'active')
  end

  # ---------------------------------------------------------------- evolving

  test "nobody can evolve on their own first turn" do
    evolution = uid_of(@engine, 0, :bloomling)

    assert_match(/first turn/, @engine.error_for(0, 'type' => 'evolve', 'card' => evolution, 'target' => 'active'))
    end_turn(@engine)
    assert_match(/first turn/, @engine.error_for(1, 'type' => 'evolve', 'card' => give(@engine, 1, :bloomling), 'target' => 'active'))
  end

  test "a Pokémon that has been in play since an earlier turn can evolve" do
    pass_turns(@engine, 2)
    evolution = uid_of(@engine, 0, :bloomling)

    @engine.perform(0, 'type' => 'evolve', 'card' => evolution, 'target' => 'active')

    assert_equal 2, @engine.active(0)['stack'].size
    assert_equal 'Bloomling', @engine.top_card(@engine.active(0)).name
  end

  test "evolving keeps the damage and the Energy" do
    pass_turns(@engine, 2)
    @engine.active(0)['damage'] = 30
    @engine.active(0)['energy'] << give(@engine, 0, :grass_energy, zone: 'discard')
    @engine.player(0)['discard'].pop

    @engine.perform(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'active')

    assert_equal 30, @engine.active(0)['damage']
    assert_equal 1, @engine.active(0)['energy'].size
  end

  test "a Pokémon can't evolve in the turn it was played" do
    pass_turns(@engine, 2)
    @engine.perform(0, 'type' => 'bench', 'card' => uid_of(@engine, 0, :sprigling))

    error = @engine.error_for(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'bench-0')

    assert_match(/turn it was played/, error)
  end

  test "a Pokémon can't evolve twice in a turn" do
    pass_turns(@engine, 2)
    @engine.perform(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'active')

    error = @engine.error_for(0, 'type' => 'evolve', 'card' => give(@engine, 0, :thornlord), 'target' => 'active')

    assert_match(/turn it was played or evolved/, error)
  end

  test "a Stage 2 evolves from the Stage 1 on a later turn" do
    pass_turns(@engine, 2)
    @engine.perform(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'active')
    pass_turns(@engine, 2)

    @engine.perform(0, 'type' => 'evolve', 'card' => give(@engine, 0, :thornlord), 'target' => 'active')

    assert_equal 'Thornlord', @engine.top_card(@engine.active(0)).name
    assert_equal 3, @engine.active(0)['stack'].size
  end

  test "an evolution has to match the Pokémon it evolves from" do
    pass_turns(@engine, 2)
    @engine.perform(0, 'type' => 'bench', 'card' => give(@engine, 0, :emberpup))
    pass_turns(@engine, 2)

    error = @engine.error_for(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :bloomling), 'target' => 'bench-0')

    assert_match(/doesn't evolve from Emberpup/, error)
  end

  test "only evolution cards evolve things" do
    pass_turns(@engine, 2)

    assert_match(/not an evolution/, @engine.error_for(0, 'type' => 'evolve', 'card' => uid_of(@engine, 0, :sprigling), 'target' => 'active'))
  end

  # ---------------------------------------------------------------- retreating

  test "retreating discards Energy equal to the Retreat Cost and swaps the Pokémon" do
    @engine.perform(0, 'type' => 'bench', 'card' => give(@engine, 0, :emberpup))
    energy = give(@engine, 0, :grass_energy, zone: 'discard')
    @engine.player(0)['discard'].delete(energy)
    @engine.active(0)['energy'] << energy
    old_active = @engine.active(0)

    @engine.perform(0, 'type' => 'retreat', 'to' => 0, 'energy' => [energy])

    assert_equal 'Emberpup', @engine.top_card(@engine.active(0)).name
    assert_same old_active, @engine.bench(0).first
    assert_empty old_active['energy']
    assert_includes @engine.player(0)['discard'], energy
  end

  test "retreating needs a Benched Pokémon and enough Energy, and happens once a turn" do
    assert_match(/no Pokémon on the Bench/, @engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => []))

    @engine.perform(0, 'type' => 'bench', 'card' => give(@engine, 0, :emberpup))
    assert_match(/costs 1 Energy/, @engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => []))
    assert_match(/attached to your Active/, @engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => [give(@engine, 0, :grass_energy)]))

    # a Pokémon with no Retreat Cost swaps for free, but still only once
    @engine.top_card(@engine.active(0)).update_columns(retreat_cost: 0)
    @engine.perform(0, 'type' => 'retreat', 'to' => 0, 'energy' => [])
    assert_match(/already retreated/, @engine.error_for(0, 'type' => 'retreat', 'to' => 0, 'energy' => []))
  end

  test "the Benched Pokémon to switch in has to exist" do
    @engine.perform(0, 'type' => 'bench', 'card' => give(@engine, 0, :emberpup))

    assert_match(/Choose a Benched Pokémon/, @engine.error_for(0, 'type' => 'retreat', 'to' => 4, 'energy' => []))
    assert_match(/Choose a Benched Pokémon/, @engine.error_for(0, 'type' => 'retreat', 'to' => 'x', 'energy' => []))
  end

  # ---------------------------------------------------------------- listing what is possible

  test "the player whose turn it is gets a list of moves, the other only concede" do
    give(@engine, 0, :grass_energy)
    types = @engine.legal_actions(0).map { |action| action['type'] }.uniq

    assert_includes types, 'bench'
    assert_includes types, 'attach'
    assert_includes types, 'end_turn'
    assert_not_includes types, 'attack' # the first player can't attack on the first turn
    assert_not_includes types, 'evolve'
    assert_equal ['concede'], @engine.legal_actions(1).map { |action| action['type'] }
  end

  test "every action in the list is accepted" do
    @engine.legal_actions(0).reject { |action| action['type'] == 'concede' }.each do |action|
      assert_nil @engine.error_for(0, action), action.inspect
    end
  end

  test "a game can be saved and loaded again in the middle" do
    @engine.perform(0, 'type' => 'attach', 'card' => give(@engine, 0, :grass_energy), 'target' => 'active')
    copy = Tcg::Engine.new(JSON.parse(@engine.state.to_json), shuffle: false)

    assert_equal @engine.legal_actions(0), copy.legal_actions(0)
    copy.perform(0, 'type' => 'end_turn')
    assert_equal 1, copy.current
    assert_equal 0, @engine.current # the original is untouched
  end

  test "the log tells what happened" do
    @engine.perform(0, 'type' => 'end_turn')

    assert_match(/ended their turn/, @engine.log.map { |entry| entry['text'] }.join("\n"))
    assert_equal 1, @engine.log.last['seat'] # the new turn belongs to seat 1
  end
end
