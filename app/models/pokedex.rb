class Pokedex < ApplicationRecord
  belongs_to :type
  belongs_to :skill
end
