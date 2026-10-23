ENV['RAILS_ENV'] ||= 'test'
require_relative "../config/environment"
require "rails/test_help"

# Fixtures replace whole tables, so never run against anything but a test database.
test_database = ActiveRecord::Base.connection_db_config.database.to_s
abort "Refusing to run the tests against #{test_database.inspect}: it is not a test database." unless test_database.match?(/_test(-\d+)?\z/)

require_relative "support/tcg_helpers"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all
  include TcgHelpers

  # Add more helper methods to be used by all tests here...

  # A legal 60 card deck from the fixtures: 4 each of four Pokemon and 22 + 22 Energy.
  # (The 16 + 44 = 60 cards need nothing above the 4 copy limit; basic Energy has no limit.)
  # With sample: true it belongs to nobody, like the sample decks of the app.
  def build_legal_deck(player: Player.create!, name: 'Test deck', sample: false)
    deck = sample ? Deck.create!(name: name, sample: true) : player.decks.create!(name: name)
    { sprigling: 4, bloomling: 4, emberpup: 4, shellpal: 4, grass_energy: 22, fire_energy: 22 }.each do |fixture, quantity|
      deck.deck_cards.create!(card: cards(fixture), quantity: quantity)
    end
    deck
  end

  # Draws the card that starts the turn of a game's current player, when one is due.
  def draw_for(game)
    engine = game.reload.engine
    game.perform!(engine.pending['seat'], 'type' => 'draw') if engine.pending && engine.pending['type'] == 'draw'
  end
end
