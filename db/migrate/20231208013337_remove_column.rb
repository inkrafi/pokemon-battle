class RemoveColumn < ActiveRecord::Migration[7.1]
  def change
    remove_column :pokemon_players, :skill_id
  end
end
