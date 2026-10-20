class RemoveGlobalHpAndPp < ActiveRecord::Migration[7.1]
  def up
    remove_column :pokemon_players, :current_hp
    remove_column :pokemon_player_skills, :current_pp

    # Left over in schema.rb without any migration or model behind them.
    drop_table :battle_histories, if_exists: true
    drop_table :pokemon_battle_details, if_exists: true
  end

  def down
    add_column :pokemon_players, :current_hp, :integer
    add_column :pokemon_player_skills, :current_pp, :integer

    execute 'UPDATE pokemon_players SET current_hp = max_hp'
    execute <<~SQL
      UPDATE pokemon_player_skills pps
      SET current_pp = s.max_pp
      FROM skills s
      WHERE s.id = pps.skill_id
    SQL
  end
end
