class AddSpeedToPokemonPlayers < ActiveRecord::Migration[7.1]
  def change
    add_column :pokemon_players, :speed, :integer
  end
end
