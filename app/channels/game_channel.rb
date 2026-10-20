# Tells the pages of an online game that the board changed, so they can load their own view.
# Only the two players of a game may listen.
class GameChannel < ApplicationCable::Channel
  def subscribed
    game = Game.of(current_player).find_by(id: params[:id])
    game ? stream_for(game) : reject
  end
end
