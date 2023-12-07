class AddDefenseToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :defense, :integer
  end
end
