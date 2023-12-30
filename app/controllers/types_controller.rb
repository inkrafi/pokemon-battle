class TypesController < ApplicationController
  def index
    @types = Type.all
  end
  
  def new 
    @type = Type.new
  end

  def create
    type = Type.new(type_params)
    if type.save
      flash[:success] = "Type #{type.name} created!"
      redirect_to types_url
    else
      render 'new'
    end
  end

  def show
    @types = Type.all
  end

  private

    def type_params
      params.require(:type).permit(:name)
    end
end
