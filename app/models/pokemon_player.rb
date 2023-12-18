class PokemonPlayer < ApplicationRecord
  belongs_to :pokedex, dependent: :destroy
  has_many   :pokemon_battle_pokemon1, class_name: 'PokemonBattle', foreign_key: 'pokemon1_id', dependent: :destroy
	has_many   :pokemon_battle_pokemon2, class_name: 'PokemonBattle', foreign_key: 'pokemon2_id', dependent: :destroy
	has_many   :pokemon_battle_pokemon_winner, class_name: 'PokemonBattle', foreign_key: 'pokemon_winner_id', dependent: :destroy
	has_many   :pokemon_battle_pokemon_loser, class_name: 'PokemonBattle', foreign_key: 'pokemon_loser_id', dependent: :destroy
  has_many   :pokemon_player_skills, dependent: :destroy
  has_many   :skills, through: :pokemon_player_skills, dependent: :destroy

  default_scope -> { order(created_at: :desc) }

  validates :name, presence: true
  validates :pokedex_id, presence: true
  validates :skill_ids, presence: true
end
