module Tcgdex
  # Copies cards of one or more sets from TCGdex into the database. Safe to run again:
  # cards are matched on their TCGdex id.
  class Importer
    Result = Struct.new(:sets, :cards, :skipped, :failed)

    def initialize(client: Client.new, logger: nil)
      @client = client
      @logger = logger
    end

    def import_sets(set_ids, standard_only: true)
      result = Result.new(0, 0, 0, [])
      set_ids.each { |set_id| import_set(set_id, standard_only: standard_only, result: result) }
      result
    end

    private

    def import_set(set_id, standard_only:, result:)
      payload = @client.set(set_id)
      card_set = CardSet.find_or_initialize_by(tcgdex_id: payload.fetch('id'))
      card_set.update!(name: payload.fetch('name'), released_on: payload['releaseDate'],
                       card_count: payload.dig('cardCount', 'official'))
      result.sets += 1
      say "#{card_set.name}: #{Array(payload['cards']).size} cards"

      Array(payload['cards']).each do |brief|
        import_card(brief.fetch('id'), card_set, standard_only: standard_only, result: result)
      end
    end

    def import_card(card_id, card_set, standard_only:, result:)
      attributes = CardMapper.call(@client.card(card_id))
      return result.skipped += 1 if standard_only && !attributes[:standard_legal]

      card = Card.find_or_initialize_by(tcgdex_id: attributes[:tcgdex_id])
      card.update!(attributes.merge(card_set: card_set))
      result.cards += 1
    rescue UnsupportedCard
      result.skipped += 1
    rescue Client::Error, ActiveRecord::RecordInvalid => error
      result.failed << "#{card_id}: #{error.message}"
    end

    def say(message)
      @logger&.call(message)
    end
  end
end
