class PokemonPlayerSkill < ApplicationRecord
  belongs_to :pokemon_player
  belongs_to :skill

  after_initialize :set_pp_values, if: :new_record?

  def set_pp_values
    # self.current_pp || self.skill.max_pp = self.skill.max_pp
    if !self.current_pp
      self.current_pp = self.skill.max_pp
    end
  end
end
