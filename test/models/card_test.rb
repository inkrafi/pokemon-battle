require "test_helper"

class CardTest < ActiveSupport::TestCase
  def pokemon_attributes(overrides = {})
    { card_set: card_sets(:test_set), tcgdex_id: 'test1-900', number: '900', name: 'Newmon', supertype: 'pokemon',
      subtype: 'basic', hp: 50, energy_types: ['Colorless'], standard_legal: true,
      attacks: [{ 'name' => 'Nudge', 'cost' => ['Colorless'], 'damage' => 10, 'has_effect' => false }], abilities: [] }.merge(overrides)
  end

  test "a card needs its basics" do
    assert Card.new(pokemon_attributes).valid?
    assert_not Card.new(pokemon_attributes(name: '')).valid?
    assert_not Card.new(pokemon_attributes(supertype: 'weapon')).valid?
    assert_not Card.new(pokemon_attributes(hp: 0)).valid?
    assert_not Card.new(pokemon_attributes(tcgdex_id: cards(:sprigling).tcgdex_id)).valid?
  end

  test "trainers and energy don't need HP" do
    assert Card.new(pokemon_attributes(supertype: 'trainer', subtype: 'item', hp: nil, attacks: [])).valid?
  end

  test "kind helpers" do
    assert cards(:sprigling).basic_pokemon?
    assert_not cards(:bloomling).basic_pokemon?
    assert cards(:grass_energy).basic_energy?
    assert cards(:healing_item).trainer?
  end

  test "the type of a card" do
    assert_equal 'Grass', cards(:sprigling).type
    assert_equal 'Fire', cards(:fire_energy).type
    assert_nil cards(:healing_item).type
  end

  test "stage and rule box labels" do
    assert_equal 'Basic', cards(:sprigling).stage_label
    assert_equal 'Stage 1', cards(:bloomling).stage_label
    assert_equal 'Mega ex', cards(:mega_rexor).rule_box
    assert_nil cards(:sprigling).rule_box
    assert_equal 'ex', Card.new(pokemon_attributes(prize_value: 2)).rule_box
  end

  test "a Pokémon is playable when it has no ability and an attack without an effect" do
    assert Card.new(pokemon_attributes).engine_ready?
    assert_not Card.new(pokemon_attributes(abilities: [{ 'name' => 'Tricks' }])).engine_ready?
    effect_only = [{ 'name' => 'Odd', 'cost' => ['Colorless'], 'damage' => 10, 'has_effect' => true }]
    assert_not Card.new(pokemon_attributes(attacks: effect_only)).engine_ready?
  end

  test "one plain attack is enough, the attacks with effects are just not usable" do
    mixed = [{ 'name' => 'Odd', 'cost' => ['Colorless'], 'damage' => 10, 'has_effect' => true },
             { 'name' => 'Plain', 'cost' => ['Colorless'], 'damage' => 10, 'has_effect' => false }]

    assert Card.new(pokemon_attributes(attacks: mixed)).engine_ready?
  end

  test "only basic Energy is playable among Energy and nothing among Trainers yet" do
    assert cards(:grass_energy).engine_ready?
    assert_not Card.new(pokemon_attributes(supertype: 'energy', subtype: 'special', energy_types: [])).engine_ready?
    assert_not cards(:healing_item).engine_ready?
  end

  test "saving a card refreshes playable" do
    card = cards(:mega_rexor)
    card.update!(abilities: [])
    assert_not card.playable # its only attack still has an effect

    card.update!(attacks: [{ 'name' => 'Plain', 'cost' => ['Colorless'], 'damage' => 10, 'has_effect' => false }])
    assert card.playable
  end

  test "scopes" do
    assert_includes Card.playable, cards(:sprigling)
    assert_not_includes Card.playable, cards(:mega_rexor)
    assert_not_includes Card.standard, cards(:retired_pup)
    assert_includes Card.named_like('sprig'), cards(:sprigling)
    assert_equal [cards(:emberpup), cards(:fire_energy)].sort_by(&:id), Card.of_type('Fire').sort_by(&:id)
    assert_equal 3, Card.energies.count
  end
end
