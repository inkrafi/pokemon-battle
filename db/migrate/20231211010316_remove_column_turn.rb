class RemoveColumnTurn < ActiveRecord::Migration[7.1]
  def change
    remove_column :pokemon_battle_details, :turn
  end
end
