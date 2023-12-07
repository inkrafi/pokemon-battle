class AddCurrentHpToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :current_hp, :integer
  end
end
