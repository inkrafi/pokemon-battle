# Card data comes from TCGdex (see lib/tcgdex). Only facts are kept: numbers, names, types,
# costs. Card art, flavour text and official effect text are deliberately not stored.
class CreateTcgCards < ActiveRecord::Migration[7.1]
  def change
    create_table :card_sets do |t|
      t.string :tcgdex_id, null: false
      t.string :name, null: false
      t.date :released_on
      t.integer :card_count

      t.timestamps
    end
    add_index :card_sets, :tcgdex_id, unique: true

    create_table :cards do |t|
      t.references :card_set, null: false, foreign_key: true
      t.string :tcgdex_id, null: false
      t.string :number, null: false
      t.string :name, null: false
      t.string :supertype, null: false           # pokemon, trainer or energy
      t.string :subtype                          # basic/stage1/stage2, item/supporter/stadium/tool, basic/special
      t.integer :hp
      t.string :energy_types, array: true, null: false, default: []
      t.string :evolves_from
      t.integer :retreat_cost
      t.string :weakness_type
      t.integer :weakness_multiplier
      t.string :resistance_type
      t.integer :resistance_amount
      t.integer :prize_value, null: false, default: 1
      t.boolean :ace_spec, null: false, default: false
      t.string :regulation_mark
      t.boolean :standard_legal, null: false, default: false
      t.string :rarity
      t.jsonb :attacks, null: false, default: []
      t.jsonb :abilities, null: false, default: []
      t.boolean :playable, null: false, default: false

      t.timestamps
    end
    add_index :cards, :tcgdex_id, unique: true
    add_index :cards, :name
    add_index :cards, [:supertype, :subtype]
    add_index :cards, :playable
  end
end
