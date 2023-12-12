class AddTurnToPokemonBattles < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_battles, :turn, :integer
  end
end
