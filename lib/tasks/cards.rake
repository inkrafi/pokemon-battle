namespace :cards do
  desc 'Import cards from TCGdex: rails "cards:import[me01,me02,mee]" (Standard legal cards only; ALL=1 for everything)'
  task :import, [:sets] => :environment do |_task, args|
    # rake splits the argument list on commas: the first goes to :sets, the rest to extras
    set_ids = ([args[:sets]] + args.extras).compact.flat_map { |value| value.to_s.split(/[,\s]+/) }.reject(&:blank?)
    set_ids = ENV['SETS'].to_s.split(/[,\s]+/).reject(&:blank?) if set_ids.empty?
    abort 'Give at least one set id, for example: rails "cards:import[me01,mee]"' if set_ids.empty?

    importer = Tcgdex::Importer.new(logger: ->(message) { puts message })
    result = importer.import_sets(set_ids, standard_only: ENV['ALL'].blank?)
    puts "Imported #{result.cards} cards from #{result.sets} sets (#{result.skipped} skipped)."
    result.failed.each { |failure| warn "Failed: #{failure}" }
  end

  desc 'Write the card database to db/cards.json (committed, so seeding needs no network)'
  task export: :environment do
    puts "Wrote #{CardSnapshot.dump(Rails.root.join('db', 'cards.json'))} cards to db/cards.json"
  end

  desc 'Load db/cards.json into the database'
  task load: :environment do
    puts "Loaded #{CardSnapshot.load(Rails.root.join('db', 'cards.json'))} cards"
  end

  desc 'Recompute which cards the game engine can play (run after implementing more card effects)'
  task refresh_playable: :environment do
    Card.find_each(&:save!)
    puts "#{Card.playable.count} of #{Card.count} cards are playable"
  end
end
