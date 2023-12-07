class PokemonBattleDetail < ApplicationRecord
  belongs_to :pokemon_player
  belongs_to :pokemon_battle
end
