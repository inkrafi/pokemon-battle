class AddModeToGames < ActiveRecord::Migration[7.1]
  def change
    # hotseat: two people share one screen. bot: seat 1 is played by the computer.
    add_column :games, :mode, :string, null: false, default: 'hotseat'
  end
end
