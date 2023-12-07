class PokemonPlayer < ApplicationRecord
  belongs_to :pokedex
  has_many   :pokemon_player_skills
  has_many   :skills, through: :pokemon_player_skills
  has_many   :pokemon_battle_details

  validates :name, presence: true

end
