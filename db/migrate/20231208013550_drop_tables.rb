class DropTables < ActiveRecord::Migration[6.1]
  def change
    drop_table :pokedex_skills
  end
end
