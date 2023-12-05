class PokemonPlayerSkill < ApplicationRecord
  belongs_to :pokemon_player
  belongs_to :skill
end
