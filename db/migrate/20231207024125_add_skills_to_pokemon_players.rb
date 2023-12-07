class AddSkillsToPokemonPlayers < ActiveRecord::Migration[6.1]
  def change
    add_reference :pokemon_players, :skill, null: true, foreign_key: true
  end
end
