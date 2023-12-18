class RenameColumn < ActiveRecord::Migration[7.1]
  def change
    rename_column :pokemon_battles, :turn, :current_turn
  end
end
