require "test_helper"

# The payloads are shaped like TCGdex answers but use invented cards and text.
class Tcgdex::CardMapperTest < ActiveSupport::TestCase
  def pokemon_payload(overrides = {})
    { 'category' => 'Pokemon', 'id' => 'zz1-007', 'localId' => '007', 'name' => 'Mapmon', 'rarity' => 'Rare',
      'hp' => 90, 'types' => ['Water'], 'stage' => 'Stage1', 'evolveFrom' => 'Mapling', 'retreat' => 2,
      'regulationMark' => 'I', 'legal' => { 'standard' => true, 'expanded' => true },
      'weaknesses' => [{ 'type' => 'Lightning', 'value' => "×2" }],
      'resistances' => [{ 'type' => 'Fighting', 'value' => '-30' }],
      'attacks' => [{ 'cost' => %w[Water Colorless], 'name' => 'Wave', 'damage' => 40 }] }.merge(overrides)
  end

  def map(payload)
    Tcgdex::CardMapper.call(payload)
  end

  test "maps a Pokémon" do
    card = map(pokemon_payload)

    assert_equal 'pokemon', card[:supertype]
    assert_equal 'stage1', card[:subtype]
    assert_equal 'zz1-007', card[:tcgdex_id]
    assert_equal '007', card[:number]
    assert_equal 90, card[:hp]
    assert_equal ['Water'], card[:energy_types]
    assert_equal 'Mapling', card[:evolves_from]
    assert_equal 2, card[:retreat_cost]
    assert_equal ['Lightning', 2], [card[:weakness_type], card[:weakness_multiplier]]
    assert_equal ['Fighting', 30], [card[:resistance_type], card[:resistance_amount]]
    assert_equal 'I', card[:regulation_mark]
    assert card[:standard_legal]
    assert_equal 1, card[:prize_value]
  end

  test "an effect that isn't understood is flagged, and its wording is never kept" do
    attack = map(pokemon_payload('attacks' => [{ 'cost' => ['Water'], 'name' => 'Drench', 'damage' => 30, 'effect' => 'Some official wording.' }]))[:attacks].first

    assert_equal({ 'name' => 'Drench', 'cost' => ['Water'], 'damage' => 30, 'modifier' => nil, 'has_effect' => true, 'effects' => [] }, attack)
    assert_not_includes attack.values, 'Some official wording.'
  end

  test "an effect that is understood becomes operations" do
    text = "Flip 2 coins. This attack does 30 damage for each heads. Your opponent's Active Pokémon is now Poisoned."
    attack = map(pokemon_payload('attacks' => [{ 'cost' => ['Water'], 'name' => 'Splash', 'damage' => '30x', 'effect' => text }]))[:attacks].first

    assert_equal false, attack['has_effect']
    assert_equal [{ 'op' => 'flip_each', 'coins' => 2, 'per' => 30 }, { 'op' => 'inflict', 'condition' => 'poisoned' }], attack['effects']
    assert_not_includes attack.to_s, 'heads'
  end

  test "an effect that is only half understood is not played" do
    text = "Your opponent's Active Pokémon is now Poisoned. Then something unheard of happens."
    attack = map(pokemon_payload('attacks' => [{ 'cost' => [], 'name' => 'Odd', 'damage' => 10, 'effect' => text }]))[:attacks].first

    assert attack['has_effect']
    assert_empty attack['effects']
  end

  test "reads damage with a modifier" do
    attacks = map(pokemon_payload('attacks' => [
      { 'name' => 'More', 'cost' => [], 'damage' => '50+' },
      { 'name' => 'Times', 'cost' => [], 'damage' => "20×" },
      { 'name' => 'Less', 'cost' => [], 'damage' => '30-' },
      { 'name' => 'Times x', 'cost' => [], 'damage' => '20x' },
      { 'name' => 'None', 'cost' => [] }
    ]))[:attacks]

    assert_equal [[50, '+'], [20, "×"], [30, '-'], [20, "×"], [nil, nil]], attacks.map { |attack| attack.values_at('damage', 'modifier') }
  end

  test "ex and Mega ex give up more Prize cards" do
    assert_equal 2, map(pokemon_payload('suffix' => 'ex', 'name' => 'Mapmon ex'))[:prize_value]
    assert_equal 3, map(pokemon_payload('suffix' => 'ex', 'name' => 'Mega Mapmon ex'))[:prize_value]
    assert_equal 3, map(pokemon_payload('suffix' => 'VMAX'))[:prize_value]
  end

  test "an Ability that isn't understood keeps only its name and keeps the Pokémon out of play" do
    abilities = map(pokemon_payload('abilities' => [{ 'type' => 'Ability', 'name' => 'Glow', 'effect' => 'Official text.' }]))[:abilities]

    assert_equal [{ 'name' => 'Glow', 'kind' => 'Ability', 'supported' => false }], abilities
  end

  test "an Ability that is understood becomes operations" do
    text = "Once during your turn, if this Pokémon is in the Active Spot, you may use this Ability. Draw 2 cards. You can't use more than 1 Glow Ability each turn."
    abilities = map(pokemon_payload('abilities' => [{ 'type' => 'Ability', 'name' => 'Glow', 'effect' => text }]))[:abilities]

    assert_equal [{ 'name' => 'Glow', 'kind' => 'Ability', 'trigger' => 'activated', 'needs' => { 'active' => true },
                    'effects' => [{ 'op' => 'draw', 'count' => 2 }], 'supported' => true }], abilities
  end

  test "an always-on Ability becomes a passive operation" do
    text = 'This Pokémon takes 30 less damage from attacks (after applying Weakness and Resistance).'
    ability = map(pokemon_payload('abilities' => [{ 'type' => 'Ability', 'name' => 'Hard', 'effect' => text }]))[:abilities].first

    assert_equal 'passive', ability['trigger']
    assert_equal [{ 'op' => 'passive', 'kind' => 'reduce_incoming', 'amount' => 30 }], ability['effects']
  end

  test "a Trainer's effect becomes operations, or nothing when it isn't understood" do
    switch = Tcgdex::CardMapper.call('category' => 'Trainer', 'id' => 'zz1-100', 'localId' => '100', 'name' => 'Swap', 'trainerType' => 'Item',
                                     'effect' => 'Switch your Active Pokémon with 1 of your Benched Pokémon.')
    odd = Tcgdex::CardMapper.call('category' => 'Trainer', 'id' => 'zz1-101', 'localId' => '101', 'name' => 'Odd', 'trainerType' => 'Item',
                                  'effect' => 'Something nobody has implemented.')

    assert_equal [{ 'op' => 'switch_own' }], switch[:effects]
    assert_equal [], odd[:effects]
  end

  test "ACE SPEC cards are recognised from the rarity" do
    assert map(pokemon_payload('rarity' => 'ACE SPEC Rare'))[:ace_spec]
    assert_not map(pokemon_payload)[:ace_spec]
  end

  test "a card that isn't Standard legal says so" do
    assert_not map(pokemon_payload('legal' => { 'standard' => false, 'expanded' => true }))[:standard_legal]
    assert_not map(pokemon_payload('legal' => nil))[:standard_legal]
  end

  test "maps a Trainer" do
    card = map('category' => 'Trainer', 'id' => 'zz1-100', 'localId' => '100', 'name' => 'Helper', 'trainerType' => 'Supporter',
               'effect' => 'Official text.', 'legal' => { 'standard' => true })

    assert_equal ['trainer', 'supporter'], [card[:supertype], card[:subtype]]
    assert_nil card[:hp]
  end

  test "maps basic Energy by its name" do
    card = map('category' => 'Energy', 'id' => 'zz1-200', 'localId' => '200', 'name' => 'Basic Fire Energy', 'energyType' => 'Normal')

    assert_equal ['energy', 'basic', ['Fire']], [card[:supertype], card[:subtype], card[:energy_types]]
    assert_equal ['Water'], map('category' => 'Energy', 'id' => 'a', 'name' => 'Water Energy', 'energyType' => 'Normal')[:energy_types]
  end

  test "Special Energy is not basic, even when the source calls it Normal" do
    card = map('category' => 'Energy', 'id' => 'zz1-201', 'localId' => '201', 'name' => 'Spark Energy', 'energyType' => 'Normal')

    assert_equal 'special', card[:subtype]
    assert_empty card[:energy_types]
  end

  test "an unknown category is refused" do
    assert_raises(Tcgdex::UnsupportedCard) { map('category' => 'Sticker', 'id' => 'x', 'name' => 'Y') }
  end
end
