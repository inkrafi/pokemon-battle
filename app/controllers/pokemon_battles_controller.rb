class PokemonBattlesController < ApplicationController
  include PokemonBattlesHelper

  def index
    @pokemon_battles = PokemonBattle.page(params[:page]).per(15)
  end

  def new
    @pokemons = PokemonPlayer.all
  end

  def create
    # Mendapatkan nilai dari params
    pokemon_1_info = params[:pokemon_1][:pokemon_player_id].split('-')
    pokemon_2_info = params[:pokemon_2][:pokemon_player_id].split('-')

    pokemon_1_id = pokemon_1_info[0].to_i
    pokemon_1_max_hp = pokemon_1_info[1].to_i

    pokemon_2_id = pokemon_2_info[0].to_i
    pokemon_2_max_hp = pokemon_2_info[1].to_i

    pokemon_battle = PokemonBattle.new(
      time: DateTime.now,
      status: "ON BATTLE",
      current_turn: 1,
      pokemon1_id: pokemon_1_id,
      pokemon2_id: pokemon_2_id,
      pokemon1_max_hp: pokemon_1_max_hp,
      pokemon2_max_hp: pokemon_2_max_hp
    )
    pokemon_battle.save

    redirect_to pokemon_battle_path(pokemon_battle.id)
  end

  def show
    @pokemon_battle = PokemonBattle.find(params[:id])
    @damage_received = params[:damage_received].to_i
    @show_damage_received = params[:show_damage_received] == 'true'

    @current_turn = @pokemon_battle.current_turn
    @attacker     = @pokemon_battle.pokemon1
    @opponent     = @pokemon_battle.pokemon2
    @winner       = @pokemon_battle.pokemon_winner
    @loser        = @pokemon_battle.pokemon_loser

    @attacker.pokemon_player_skills.order(:id)
    @opponent.pokemon_player_skills.order(:id)
  end

  def attack
    pokemon_battle_id = params[:pokemon_battle][:pokemon_battle_id]
    skill_id = params[:pokemon_battle][:skill_id]
    current_turn = params[:current_turn].to_i

    pokemon_battle = PokemonBattle.find(pokemon_battle_id)
    skill = Skill.find(skill_id)

    attacker, opponent = determine_players(pokemon_battle_id, current_turn)

    attacker_skill = PokemonPlayerSkill.find_by(pokemon_player: attacker, skill: skill)

    # Ensure that there is a valid attacker_skill and current_pp is greater than 0
    if attacker_skill.present? && attacker_skill.current_pp > 0
      attacker_skill.update(current_pp: attacker_skill.current_pp - 1)
    end
    attacker_skill.save

    new_turn = current_turn + 1
    pokemon_battle.update(current_turn: new_turn)

    # Menghitung damage dengan calculate_damage (rumusnya ada di helper)
    damage = calculate_damage(skill.power, attacker.attack, opponent.defense)

    update_hp = [opponent.current_hp - damage, 0].max
    opponent.update(current_hp: update_hp)

    # Memeriksa apakah battle sudah selesai
    check_battle_status(pokemon_battle_id)

    redirect_to pokemon_battle_path(pokemon_battle_id, show_damage_received: true, damage_received: damage)
  end

  def history
    @pokemon_battles = PokemonBattle.page(params[:page]).per(15)
    @battle_results = []

    @pokemon_battles.each do |battle|
      winner = battle.pokemon_winner
      loser = battle.pokemon_loser

      battle_result = {
        battle_id: battle.id,
        date: battle.time,
        winner_name: winner&.name, 
        loser_name: loser&.name,
        turn: battle.current_turn,
        status: battle.status
      }

      @battle_results << battle_result
    end
  end
end
