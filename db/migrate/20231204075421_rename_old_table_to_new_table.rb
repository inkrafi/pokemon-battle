class RenameOldTableToNewTable < ActiveRecord::Migration[6.1]
  def change
    rename_table :pokemons, :pokemon_players
  end
end
