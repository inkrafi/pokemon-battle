class AddAttackToPokemonPlayers < ActiveRecord::Migration[7.1]
  def change
    add_column :pokemon_players, :attack, :integer
  end
end
