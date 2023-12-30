class SkillsController < ApplicationController
  def index
    @skills = Skill.all
  end

  def new 
    @skill = Skill.new
    @types = Type.all
  end

  def create 
    skill = Skill.new(skill_params)
    if skill.save
      flash[:success] = "skill #{skill.name} created!"
      redirect_to skills_url
    else
      render 'new'
    end
  end

  def show
    @skill = Skill.find(params[:id])
  end

  private

    def skill_params
      params.require(:skill).permit(:name, :power, :max_pp, :type_id)
    end
end
