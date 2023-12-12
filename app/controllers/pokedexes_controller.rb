class PokedexesController < ApplicationController
  def index
    @pokedexes = Pokedex.all.order(:id)
  end

  def show
    @pokedex = Pokedex.find(params[:id])
  end

  def new
    @pokedex = Pokedex.new
    @types = Type.all
  end

  def create
    pokedex = Pokedex.new(pokedex_params)
    if pokedex.save
      flash[:success] = "Pokedex #{pokedex.name} created!"
      redirect_to pokedexes_url
    else
      render 'new'
    end
  end

  def edit
    @pokedex = Pokedex.find(params[:id])
    @types = Type.all
  end

  def update
    @pokedex = Pokedex.find(params[:id])
    if @pokedex.update(pokedex_params)
      flash[:success] = 'Pokedex updated.'
      redirect_to pokedexes_url
    else
      render 'edit'
    end
  end

  def destroy
    @pokedex = Pokedex.find(params[:id])
    @pokedex.destroy
    flash[:success] = 'Pokedex deleted.'
    redirect_to pokedexes_url
  end

  private

    def pokedex_params
      params.require(:pokedex).permit(:name, :image_url, :base_hp, :base_attack, :base_defense, :base_speed, :type_id)
    end

end
