class CreatePokedexes < ActiveRecord::Migration[6.1]
  def change
    create_table :pokedexes do |t|
      t.string :name
      t.integer :hp
      t.integer :attack
      t.integer :defense
      t.integer :speed
      t.string :image_url

      t.timestamps
    end
  end
end
