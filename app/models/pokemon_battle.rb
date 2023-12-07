class PokemonBattle < ApplicationRecord
  has_many :pokemon_battle_details

  validates :time, presence: true
  validates :status, presence: true
end
