class CreatePokedexSkills < ActiveRecord::Migration[6.1]
  def change
    create_table :pokedex_skills do |t|
      t.references :pokedex, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
