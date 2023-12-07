class CreatePokemonBattleDetails < ActiveRecord::Migration[6.1]
  def change
    create_table :pokemon_battle_details do |t|
      t.references :pokemon_battle, null: false, foreign_key: true
      t.references :pokemon_player, null: false, foreign_key: true
      t.string :result, null: true

      t.timestamps
    end
  end
end
