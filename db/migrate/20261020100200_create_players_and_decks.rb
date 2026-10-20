class CreatePlayersAndDecks < ActiveRecord::Migration[7.1]
  def change
    # Guests: identified by a cookie, no password.
    create_table :players do |t|
      t.string :token, null: false
      t.string :name, null: false

      t.timestamps
    end
    add_index :players, :token, unique: true

    create_table :decks do |t|
      t.references :player, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    create_table :deck_cards do |t|
      t.references :deck, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1

      t.timestamps
    end
    add_index :deck_cards, [:deck_id, :card_id], unique: true
  end
end
