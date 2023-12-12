class AddCurrentPpToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :current_pp, :integer
  end
end
