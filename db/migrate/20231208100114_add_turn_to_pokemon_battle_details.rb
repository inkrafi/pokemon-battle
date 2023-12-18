class AddTurnToPokemonBattleDetails < ActiveRecord::Migration[7.1]
  def change
    add_column :pokemon_battle_details, :turn, :string
  end
end
