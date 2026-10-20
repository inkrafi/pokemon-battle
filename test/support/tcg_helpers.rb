# Helpers to set up games for the rules tests.
#
# With shuffle: false a deck is dealt in the order given, so the opening hand is predictable:
# the mixed deck below deals 4 Sprigling and 3 Bloomling.
module TcgHelpers
  def mixed_deck_ids
    list = ->(fixture, count) { [cards(fixture).id] * count }
    list.(:sprigling, 4) + list.(:bloomling, 4) + list.(:emberpup, 4) + list.(:shellpal, 4) +
      list.(:grass_energy, 22) + list.(:fire_energy, 22)
  end

  def start_game(first_player: 0, seed: 1, shuffle: false, decks: [mixed_deck_ids, mixed_deck_ids])
    Tcg::Engine.start(decks: decks, first_player: first_player, rng: Random.new(seed), shuffle: shuffle)
  end

  # Puts a copy of a card in a zone of a seat and returns its uid. +card+ is a fixture name or a Card.
  def give(engine, seat, card, zone: 'hand')
    card = cards(card) if card.is_a?(Symbol)
    engine.catalog[card.id] = card
    engine.state['cards'] << card.id
    uid = engine.state['cards'].size - 1
    engine.player(seat)[zone] << uid
    uid
  end

  # The first uid of a card in a zone of a seat, or nil.
  def uid_of(engine, seat, fixture, zone: 'hand')
    card_id = cards(fixture).id
    engine.player(seat)[zone].find { |uid| engine.state['cards'][uid] == card_id }
  end

  # Both players place a Basic Pokemon in the Active Spot and the game begins.
  # +actives+ names the fixture each seat puts forward.
  def start_play(first_player: 0, actives: %i[sprigling sprigling], **options)
    engine = start_game(first_player: first_player, **options)
    2.times do |seat|
      uid = uid_of(engine, seat, actives[seat]) || give(engine, seat, actives[seat])
      engine.perform(seat, 'type' => 'setup', 'active' => uid, 'bench' => [])
    end
    engine
  end

  # Puts a Pokemon straight into play: 'active' replaces the Active Pokemon (which goes to the
  # discard pile), anything else adds to the Bench.
  def put_in_play(engine, seat, card, where: :bench, since: 0, damage: 0)
    uid = give(engine, seat, card, zone: 'discard')
    engine.player(seat)['discard'].delete(uid)
    slot = { 'stack' => [uid], 'energy' => [], 'damage' => damage, 'since' => since }
    if where == :active
      old = engine.player(seat)['active']
      engine.player(seat)['discard'].concat(old['stack'], old['energy']) if old
      engine.player(seat)['active'] = slot
    else
      engine.player(seat)['bench'] << slot
    end
    slot
  end

  def attach_directly(engine, slot, fixture, count = 1)
    count.times { slot['energy'] << give(engine, 0, fixture, zone: 'discard').tap { |uid| engine.player(0)['discard'].delete(uid) } }
  end

  # Passes the turn back and forth until it is +seat+'s turn again, +turns+ turns later.
  def pass_turns(engine, turns)
    turns.times { engine.perform(engine.current, 'type' => 'end_turn') }
  end

  # A card made on the spot, for rules that need an unusual card.
  def make_card(name:, hp: 100, type: 'Colorless', prize_value: 1, attacks: [], **overrides)
    Card.create!({ card_set: card_sets(:test_set), tcgdex_id: "made-#{SecureRandom.hex(4)}", number: '900', name: name,
                   supertype: 'pokemon', subtype: 'basic', hp: hp, energy_types: [type], retreat_cost: 1,
                   prize_value: prize_value, standard_legal: true, attacks: attacks, abilities: [] }.merge(overrides))
  end

  # A Trainer card made on the spot. +effects+ are the operations (see Tcg::TrainerRules).
  def make_trainer(name, subtype, *effects)
    Card.create!(card_set: card_sets(:test_set), tcgdex_id: "made-#{SecureRandom.hex(4)}", number: '901', name: name,
                 supertype: 'trainer', subtype: subtype, standard_legal: true, effects: effects)
  end

  def attack(name: 'Hit', cost: ['Colorless'], damage: 10, effects: [])
    { 'name' => name, 'cost' => cost, 'damage' => damage, 'modifier' => nil, 'has_effect' => false, 'effects' => effects }
  end
end
