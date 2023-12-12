class ChangeDataType < ActiveRecord::Migration[6.1]
  def change
    change_column :pokemon_battle_details, :turn, 'integer USING CAST(turn AS integer)'
  end
end
