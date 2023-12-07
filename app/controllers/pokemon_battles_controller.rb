class PokemonBattlesController < ApplicationController
  def index
    @pokemon_battles = PokemonBattle.all
  end

  def new
    @pokemons = PokemonPlayer.all
  end

  def create
    pokemon_battle = PokemonBattle.new(
      time: DateTime.now,
      status: "ON BATTLE"
    )

    battle_detail_1 = pokemon_battle.pokemon_battle_details.build(
      pokemon_player_id: params[:pokemon_1][:pokemon_player_id]
    )
    battle_detail_2 = pokemon_battle.pokemon_battle_details.build(
      pokemon_player_id: params[:pokemon_2][:pokemon_player_id]
    )
    pokemon_battle.save
    redirect_to pokemon_battle_path(pokemon_battle.id)
  end

  def show
    @pokemon_battle = PokemonBattle.find(params[:id])
    @pokemon_battle_details = @pokemon_battle.pokemon_battle_details.where(pokemon_battle_id: @pokemon_battle.id)
  end

end
