class CreateSkills < ActiveRecord::Migration[6.1]
  def change
    create_table :skills do |t|
      t.string :name
      t.integer :power
      t.integer :max_pp
      t.references :type, null: false, foreign_key: true

      t.timestamps
    end
  end
end
