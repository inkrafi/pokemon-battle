class RenamePokedexStats < ActiveRecord::Migration[6.1]
  def change
    change_table(:pokedexes) do |t|
      t.rename(:hp, :base_hp)
      t.rename(:attack, :base_attack)
      t.rename(:defense, :base_defense)
      t.rename(:speed, :base_speed)

      # other column transformations
    end
  end
end
