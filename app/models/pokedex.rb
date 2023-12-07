class Pokedex < ApplicationRecord
  belongs_to :type
  has_many :pokemon_players
end
