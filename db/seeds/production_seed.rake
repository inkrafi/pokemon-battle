# db/seeds/production_seed.rake

namespace :db do
  namespace :seed do
    desc 'Seed the production database'
    task :production => :environment do
      # Menambahkan data ke tabel types
      types_data = [
        "Normal", "Fire", "Water", "Electric", "Grass",
        "Ice", "Fighting", "Poison", "Ground", "Flying",
        "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Fairy"
      ]

      types_data.each do |type_name|
        Type.create(name: type_name)
      end

      # Menambahkan data ke tabel skills
      skills_data = [
        { name: "Pound", power: 40, max_pp: 35, type_id: Type.find_by(name: "Normal").id },
        { name: "Karate-Chop", power: 50, max_pp: 25, type_id: Type.find_by(name: "Fighting").id },
        { name: "Double-Slap", power: 15, max_pp: 10, type_id: Type.find_by(name: "Normal").id },
        { name: "Comet-Punch", power: 18, max_pp: 15, type_id: Type.find_by(name: "Normal").id },
        { name: "Mega-Punch", power: 80, max_pp: 20, type_id: Type.find_by(name: "Normal").id },
        { name: "Pay-Day", power: 40, max_pp: 20, type_id: Type.find_by(name: "Normal").id },
        { name: "Fire-Punch", power: 75, max_pp: 15, type_id: Type.find_by(name: "Fire").id },
        { name: "Ice-Punch", power: 75, max_pp: 15, type_id: Type.find_by(name: "Ice").id }
      ]

      skills_data.each do |skill|
        Skill.create(skill)
      end
    end
  end
end
