class PokemonBattleDetailsController < ApplicationController
  def new
    @pokemon_battle_detail = PokemonBattleDetail.new
  end

  def show
    # Tampilkan hasil battle
    @pokemon_battle_detail = PokemonBattleDetail.find(params[:id])
  end

end
