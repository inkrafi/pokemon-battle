class AddTypeToPokedexes < ActiveRecord::Migration[7.1]
  def change
    add_reference :pokedexes, :type, null: true, foreign_key: true
  end
end
