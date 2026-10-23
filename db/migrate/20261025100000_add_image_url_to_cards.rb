class AddImageUrlToCards < ActiveRecord::Migration[7.1]
  def change
    # TCGdex's base URL for the card picture; add "/low.webp" or "/high.webp" to load it
    add_column :cards, :image_url, :string
  end
end
