class Pokemons2Controller < ApplicationController
  def index
    @pokedexes = Pokedex.all
    @skills = Skill.all
  end
end
