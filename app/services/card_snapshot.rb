# The card database as one JSON file (db/cards.json). Seeding from it needs no network, so a
# fresh install has cards at once. It holds the same facts as the cards table and nothing else.
module CardSnapshot
  SET_FIELDS  = %w[tcgdex_id name released_on card_count].freeze
  CARD_FIELDS = %w[tcgdex_id number name supertype subtype hp energy_types evolves_from retreat_cost
                   weakness_type weakness_multiplier resistance_type resistance_amount prize_value ace_spec
                   regulation_mark standard_legal rarity attacks abilities effects image_url].freeze

  def self.dump(path)
    data = {
      'sets' => CardSet.order(:tcgdex_id).map { |set| set.attributes.slice(*SET_FIELDS) },
      'cards' => Card.includes(:card_set).order(:tcgdex_id).map do |card|
        card.attributes.slice(*CARD_FIELDS).merge('set' => card.card_set.tcgdex_id)
      end
    }
    File.write(path, JSON.pretty_generate(data))
    data['cards'].size
  end

  def self.load(path)
    data = JSON.parse(File.read(path))

    sets = data.fetch('sets').to_h do |attributes|
      set = CardSet.find_or_initialize_by(tcgdex_id: attributes['tcgdex_id'])
      set.update!(attributes)
      [set.tcgdex_id, set]
    end

    data.fetch('cards').each do |attributes|
      card = Card.find_or_initialize_by(tcgdex_id: attributes['tcgdex_id'])
      card.update!(attributes.except('set').merge('card_set' => sets.fetch(attributes['set'])))
    end
    data['cards'].size
  end
end
