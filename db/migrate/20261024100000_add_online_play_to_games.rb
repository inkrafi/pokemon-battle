class AddOnlinePlayToGames < ActiveRecord::Migration[7.1]
  def change
    # An online game waits for a second player: the host's deck is kept until they join.
    add_reference :games, :host_deck, foreign_key: { to_table: :decks, on_delete: :nullify }, null: true
    add_column :games, :invite_token, :string
    add_index :games, :invite_token, unique: true
  end
end
