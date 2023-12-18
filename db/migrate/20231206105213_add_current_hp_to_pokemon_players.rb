class AddCurrentHpToPokemonPlayers < ActiveRecord::Migration[7.1]
  def change
    add_column :pokemon_players, :current_hp, :integer
  end
end
