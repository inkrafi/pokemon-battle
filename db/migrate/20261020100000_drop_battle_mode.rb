# The app is now the Pokemon trading card game. The video-game style battle mode
# (pokedex, pokemon, skills, battles) is gone, so are its tables.
# This deletes that data for good; there is no way back.
class DropBattleMode < ActiveRecord::Migration[7.1]
  TABLES = %i[
    battle_logs battle_skills pokemon_battles pokemon_player_skills
    pokemon_players skills pokedexes types
  ].freeze

  def up
    TABLES.each { |table| drop_table table, if_exists: true, force: :cascade }
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'The battle mode data was deleted and cannot be restored.'
  end
end
