class PokemonBattleDetail < ApplicationRecord
  belongs_to :pokemon_player
  belongs_to :pokemon_battle

  def self.find_opponent_detail(detail_id)
    battle_detail = find(detail_id)
    opponent_turn = battle_detail.turn.odd? ? battle_detail.turn + 1 : battle_detail.turn - 1
    find_by(pokemon_battle_id: battle_detail.pokemon_battle_id, turn: opponent_turn)
  end
end
