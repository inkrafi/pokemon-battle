# HP and PP used to live on pokemon_players / pokemon_player_skills, so they were
# shared by every battle and never reset. They now belong to a single battle.
class CreateBattleState < ActiveRecord::Migration[7.1]
  def up
    add_column :pokemon_battles, :pokemon1_hp, :integer
    add_column :pokemon_battles, :pokemon2_hp, :integer

    add_index :pokemon_battles, :pokemon1_id
    add_index :pokemon_battles, :pokemon2_id
    add_index :pokemon_battles, :pokemon_winner_id
    add_index :pokemon_battles, :pokemon_loser_id

    create_table :battle_skills do |t|
      t.references :pokemon_battle, null: false, foreign_key: true
      t.references :pokemon_player, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true
      t.integer :current_pp, null: false

      t.timestamps
    end
    add_index :battle_skills, [:pokemon_battle_id, :pokemon_player_id, :skill_id],
              unique: true, name: 'index_battle_skills_on_battle_player_skill'

    create_table :battle_logs do |t|
      t.references :pokemon_battle, null: false, foreign_key: true
      t.integer :turn, null: false
      t.integer :target_id
      t.integer :damage, null: false, default: 0
      t.string :message, null: false

      t.timestamps
    end

    backfill_battle_state
  end

  def down
    drop_table :battle_logs
    drop_table :battle_skills

    remove_index :pokemon_battles, :pokemon_loser_id
    remove_index :pokemon_battles, :pokemon_winner_id
    remove_index :pokemon_battles, :pokemon2_id
    remove_index :pokemon_battles, :pokemon1_id

    remove_column :pokemon_battles, :pokemon2_hp
    remove_column :pokemon_battles, :pokemon1_hp
  end

  private

  # Carry the current state of existing battles over to the new columns/tables.
  def backfill_battle_state
    execute <<~SQL
      UPDATE pokemon_battles b
      SET pokemon1_max_hp = p.max_hp
      FROM pokemon_players p
      WHERE p.id = b.pokemon1_id AND b.pokemon1_max_hp IS NULL
    SQL

    execute <<~SQL
      UPDATE pokemon_battles b
      SET pokemon2_max_hp = p.max_hp
      FROM pokemon_players p
      WHERE p.id = b.pokemon2_id AND b.pokemon2_max_hp IS NULL
    SQL

    execute <<~SQL
      UPDATE pokemon_battles b
      SET pokemon1_hp = COALESCE((SELECT p.current_hp FROM pokemon_players p WHERE p.id = b.pokemon1_id), 0),
          pokemon2_hp = COALESCE((SELECT p.current_hp FROM pokemon_players p WHERE p.id = b.pokemon2_id), 0)
    SQL

    # Only unfinished battles still need their move PP.
    execute <<~SQL
      INSERT INTO battle_skills (pokemon_battle_id, pokemon_player_id, skill_id, current_pp, created_at, updated_at)
      SELECT b.id, pps.pokemon_player_id, pps.skill_id, MIN(COALESCE(pps.current_pp, s.max_pp)), NOW(), NOW()
      FROM pokemon_battles b
      JOIN pokemon_player_skills pps ON pps.pokemon_player_id IN (b.pokemon1_id, b.pokemon2_id)
      JOIN skills s ON s.id = pps.skill_id
      WHERE b.status = 'ON BATTLE'
      GROUP BY b.id, pps.pokemon_player_id, pps.skill_id
    SQL
  end
end
