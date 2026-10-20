module ApplicationCable
  # A connection belongs to a guest: the browser's signed player cookie says which one.
  class Connection < ActionCable::Connection::Base
    identified_by :current_player

    def connect
      self.current_player = Player.find_by(token: cookies.signed[:player_token]) || reject_unauthorized_connection
    end
  end
end
