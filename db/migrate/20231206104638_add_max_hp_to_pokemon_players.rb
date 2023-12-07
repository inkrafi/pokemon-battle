class AddMaxHpToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :max_hp, :integer
  end
end
