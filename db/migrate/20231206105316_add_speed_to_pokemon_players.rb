class AddSpeedToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :speed, :integer
  end
end
