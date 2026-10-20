class AddEffectsToCards < ActiveRecord::Migration[7.1]
  def change
    # What a Trainer card does, as operations for Tcg::Engine (never the printed wording)
    add_column :cards, :effects, :jsonb, default: [], null: false
  end
end
