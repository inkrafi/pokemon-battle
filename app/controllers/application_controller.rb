class ApplicationController < ActionController::Base
  helper_method :current_player

  private

  # Visitors are guests: a Player is created the first time one is needed and remembered in a
  # signed cookie. No account, no password.
  def current_player
    @current_player ||= Player.find_by(token: cookies.signed[:player_token]) || create_player
  end

  # The guest of this browser, if it has one yet. Never creates one.
  def existing_player
    @existing_player ||= Player.find_by(token: cookies.signed[:player_token])
  end

  def create_player
    Player.create!.tap do |player|
      cookies.permanent.signed[:player_token] = { value: player.token, httponly: true, same_site: :lax }
    end
  end
end
