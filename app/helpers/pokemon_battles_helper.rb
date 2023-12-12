module PokemonBattlesHelper

  def determine_players(pokemon_battle_id, current_turn)
    # Mendapatkan data pemain 1 dan pemain 2 dari battle
    player_1 = PokemonBattle.find(pokemon_battle_id).pokemon1
    player_2 = PokemonBattle.find(pokemon_battle_id).pokemon2

    if current_turn.to_i.odd?
      return player_1, player_2
    else
      return player_2, player_1
    end
  end

  def calculate_damage(power, attack, defense)
    #                lvl crit                                                  stab type random
    damage = (((((2 * 1 * 1 / 5) + 2) * power * (attack / defense)) / 50) + 2) * 1.5 * 1 * 1
    damage = [damage, 1].max
    damage.to_i
  end

  def check_battle_status(pokemon_battle_id)
    pokemon_battle = PokemonBattle.find(pokemon_battle_id)

    attacker, opponent = determine_players(pokemon_battle_id, pokemon_battle.current_turn)

    if attacker.current_hp <= 0 || opponent.current_hp <= 0
      pokemon_battle.update(status: "FINISHED")

      if attacker.current_hp <= 0
        pokemon_battle.update(pokemon_winner_id: opponent.id, pokemon_loser_id: attacker.id)
      elsif opponent.current_hp <= 0
        pokemon_battle.update(pokemon_winner_id: attacker.id, pokemon_loser_id: opponent.id)
      end
    end
  end

end
