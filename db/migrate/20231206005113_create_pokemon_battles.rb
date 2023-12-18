class CreatePokemonBattles < ActiveRecord::Migration[7.1]
  def change
    create_table :pokemon_battles do |t|
      t.datetime :time
      t.string :status

      t.timestamps
    end
  end
end
