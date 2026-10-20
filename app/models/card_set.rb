class CardSet < ApplicationRecord
  has_many :cards, dependent: :restrict_with_error

  validates :tcgdex_id, presence: true, uniqueness: true
  validates :name, presence: true
end
