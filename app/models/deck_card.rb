class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :card_id, uniqueness: { scope: :deck_id }
end
