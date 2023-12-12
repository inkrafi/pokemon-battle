class RemoveCurrentPp < ActiveRecord::Migration[6.1]
  def change
    remove_column :pokemon_players, :current_pp
  end
end
