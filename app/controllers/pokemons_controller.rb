class PokemonsController < ApplicationController

  def index
    @pokedexes = Pokedex.all
    @skills = Skill.all
  end

  def new
  end

  def create
    @pokemon = PokemonPlayer.new(pokemon_params)
    @pokemon.save
    redirect_to pokemons2_index_url
  end

  private

  def pokemon_params
    params.require(:pokemon).permit(:name, :pokedex_id)
  end

end
