class CreateGames < ActiveRecord::Migration[7.1]
  def change
    # A game in progress. The whole board lives in one JSON document that the rules engine
    # (app/services/tcg) reads and writes; the record around it says who is playing.
    create_table :games do |t|
      t.references :player0, foreign_key: { to_table: :players }
      t.references :player1, foreign_key: { to_table: :players }
      t.jsonb :state, null: false, default: {}
      t.string :status, null: false, default: 'setup' # setup, play or finished
      t.integer :winner_seat

      t.timestamps
    end

    # Sample decks belong to nobody: everyone can copy them.
    change_column_null :decks, :player_id, true
    add_column :decks, :sample, :boolean, null: false, default: false
  end
end
