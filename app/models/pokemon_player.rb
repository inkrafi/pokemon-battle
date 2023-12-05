class PokemonPlayer < ApplicationRecord
  belongs_to :pokedex
  belongs_to :skill
  has_many   :pokemon_player_skills
  has_many   :skills, through: :pokemon_player_skills

  def skill_ids
    self.skills.pluck(:id)
  end

end
