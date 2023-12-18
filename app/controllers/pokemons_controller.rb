class PokemonsController < ApplicationController

  def index
    @pokemons = PokemonPlayer.page(params[:page]).per(12)
  end

  def new
    @pokedexes = Pokedex.all.order(:id)
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
      flash[:success] = "Pokemon #{pokemon.name} added to the list!"
      redirect_to pokemons_url
    else
      render 'new'
    end
  end

  def show
    @pokemon = PokemonPlayer.find(params[:id])
  end

  def destroy
    pokemon = PokemonPlayer.find(params[:id])
    pokemon.destroy
    flash[:success] = "Pokemon #{pokemon.name} deleted."
    redirect_to pokemons_url
  end

  def edit
    @pokemon = PokemonPlayer.find(params[:id])
    @pokedexes = Pokedex.all.order(:id)
    @skills = Skill.all
  end

  def update
    @pokemon = PokemonPlayer.find(params[:id])
    if @pokemon.update(pokemon_params)
      flash[:success] = 'Pokemon updated.'
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
