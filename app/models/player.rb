# A guest. Identified by a cookie, no password, so decks and games belong to a browser.
class Player < ApplicationRecord
  has_secure_token :token
  has_many :decks, dependent: :destroy

  before_validation :set_default_name, on: :create

  validates :name, presence: true, length: { maximum: 24 }

  private

  def set_default_name
    self.name = "Trainer #{SecureRandom.random_number(9000) + 1000}" if name.blank?
  end
end
