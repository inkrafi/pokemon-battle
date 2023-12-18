class PokemonBattle < ApplicationRecord
  belongs_to :pokemon1, class_name: 'PokemonPlayer',
												foreign_key: 'pokemon1_id'
	belongs_to :pokemon2, class_name: 'PokemonPlayer',
												foreign_key: 'pokemon2_id'
	belongs_to :pokemon_winner, class_name: 'PokemonPlayer',
												foreign_key: 'pokemon_winner_id',
												optional: true
	belongs_to :pokemon_loser, class_name: 'PokemonPlayer',
												foreign_key: 'pokemon_loser_id',
												optional: true

  default_scope -> { order(created_at: :desc) }

  validates :time, presence: true
  validates :status, presence: true
  validates :pokemon1_id, presence: true
	validates :pokemon2_id, presence: true
	validates :current_turn, presence: true
end
