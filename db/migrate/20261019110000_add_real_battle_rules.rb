# Groundwork for rules closer to the main games: levels (stats follow the real stat formula),
# move accuracy, a second type per Pokedex entry and a fixed first mover per battle.
class AddRealBattleRules < ActiveRecord::Migration[7.1]
  def up
    add_column :pokemon_players, :level, :integer, null: false, default: 50
    add_column :skills, :accuracy, :integer, null: false, default: 100
    add_reference :pokedexes, :secondary_type, foreign_key: { to_table: :types }, null: true
    add_column :pokemon_battles, :first_mover_id, :integer

    # Recompute the stats of existing Pokemon with the games' formula at level 50
    # (31 IVs, no EVs, neutral nature). Before, the base stats were used as they were.
    execute <<~SQL
      UPDATE pokemon_players p
      SET max_hp  = ((2 * d.base_hp + 31) * p.level / 100) + p.level + 10,
          attack  = ((2 * d.base_attack + 31) * p.level / 100) + 5,
          defense = ((2 * d.base_defense + 31) * p.level / 100) + 5,
          speed   = ((2 * d.base_speed + 31) * p.level / 100) + 5
      FROM pokedexes d
      WHERE d.id = p.pokedex_id
    SQL

    # Existing battles keep the order they were played in: the faster Pokemon, Player 1 on a tie.
    execute <<~SQL
      UPDATE pokemon_battles b
      SET first_mover_id = CASE
        WHEN COALESCE((SELECT speed FROM pokemon_players WHERE id = b.pokemon1_id), 0) >=
             COALESCE((SELECT speed FROM pokemon_players WHERE id = b.pokemon2_id), 0)
        THEN b.pokemon1_id ELSE b.pokemon2_id END
    SQL
  end

  def down
    remove_column :pokemon_battles, :first_mover_id
    remove_reference :pokedexes, :secondary_type, foreign_key: { to_table: :types }
    remove_column :skills, :accuracy
    remove_column :pokemon_players, :level

    execute <<~SQL
      UPDATE pokemon_players p
      SET max_hp = d.base_hp, attack = d.base_attack, defense = d.base_defense, speed = d.base_speed
      FROM pokedexes d
      WHERE d.id = p.pokedex_id
    SQL
  end
end
