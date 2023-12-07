class PokemonsController < ApplicationController

  def index
    @pokemons = PokemonPlayer.all
  end

  def new
    @pokedexes = Pokedex.all
    @skills = Skill.all
  end

  def create
    pokedex = Pokedex.find(params[:pokemon][:pokedex_id])

    # Ambil atribut dari formulir dan objek Pokedex
    pokemon_attributes = pokemon_params.merge(
      max_hp: pokedex.base_hp,
      current_hp: pokedex.base_hp,
      attack: pokedex.base_attack,
      defense: pokedex.base_defense,
      speed: pokedex.base_speed
    )

    # Buat objek PokemonPlayer dengan atribut yang telah digabungkan
    pokemon = PokemonPlayer.new(pokemon_attributes)

    if pokemon.save
      redirect_to pokemons_url, notice: 'Pokemon berhasil dibuat.'
    else
      render 'new'
    end
  end

  def show
    @pokemon = PokemonPlayer.find(params[:id])
  end

  def destroy
    @pokemon = PokemonPlayer.find(params[:id])
    @pokemon.destroy
    redirect_to pokemons_url
  end

  def edit
    @pokemon = PokemonPlayer.find(params[:id])
    @pokedexes = Pokedex.all
    @skills = Skill.all
  end

  def update
    @pokemon = PokemonPlayer.find(params[:id])
    if @pokemon.update(pokemon_params)
      redirect_to pokemons_url
    else
      render 'edit'
    end
  end

  private

    def pokemon_params
      params.require(:pokemon).permit(:name, :pokedex_id, skill_ids: [])
    end

end
