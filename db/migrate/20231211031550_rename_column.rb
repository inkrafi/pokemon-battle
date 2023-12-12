class RenameColumn < ActiveRecord::Migration[6.1]
  def change
    rename_column :pokemon_battles, :turn, :current_turn
  end
end
