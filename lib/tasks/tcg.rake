namespace :tcg do
  desc 'Build (or rebuild) the sample decks from the cards in the database'
  task sample_decks: :environment do
    SampleDecks.create!.each { |deck| puts "#{deck.name}: #{deck.card_count} cards, legal: #{deck.legal?}" }
  end

  desc 'Play random games between the sample decks to check the rules: rails "tcg:simulate[20]"'
  task :simulate, [:games] => :environment do |_task, args|
    decks = Deck.samples.to_a
    abort 'No sample decks yet. Run rails tcg:sample_decks first.' if decks.size < 2

    results = Hash.new(0)
    turns = []
    (args[:games] || 20).to_i.times do |index|
      engine = Tcg::Engine.start(decks: decks.map(&:card_ids), rng: Random.new(index))
      Tcg::RandomBot.new(rng: Random.new(index)).play_out(engine)
      results["#{decks[engine.winner].name} by #{engine.win_reason}"] += 1
      turns << engine.turn_number
    end

    results.sort_by { |_, count| -count }.each { |label, count| puts "#{count}x #{label}" }
    puts "Turns per game: #{turns.min} to #{turns.max}, average #{turns.sum / turns.size}"
  end
end
