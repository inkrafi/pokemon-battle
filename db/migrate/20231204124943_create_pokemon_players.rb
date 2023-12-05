class CreatePokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    create_table :pokemon_players do |t|
      t.string :name
      t.references :pokedex, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true

      t.timestamps
    end
  end
end
