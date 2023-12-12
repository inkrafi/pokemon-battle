class AddPokemonToPokemonBattles < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_battles, :pokemon1_id, :integer
    add_column :pokemon_battles, :pokemon2_id, :integer
    add_column :pokemon_battles, :pokemon_winner_id, :integer
    add_column :pokemon_battles, :pokemon_loser_id, :integer
    add_column :pokemon_battles, :pokemon1_max_hp, :integer
    add_column :pokemon_battles, :pokemon2_max_hp, :integer
  end
end
