class Skill < ApplicationRecord
  belongs_to :type
  has_many   :pokemon_player_skills
  has_many   :pokemon_players, through: :pokemon_player_skills
end
