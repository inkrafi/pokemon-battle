class AddCurrentPpToPokemonPlayerSkills < ActiveRecord::Migration[7.1]
  def change
    add_column :pokemon_player_skills, :current_pp, :integer
  end
end
