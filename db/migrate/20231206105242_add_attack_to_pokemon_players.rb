class AddAttackToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :pokemon_players, :attack, :integer
  end
end
