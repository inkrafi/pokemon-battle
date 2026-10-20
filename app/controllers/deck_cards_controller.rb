class DeckCardsController < ApplicationController
  before_action :set_deck

  def create
    change = @deck.add_card(Card.find(params[:card_id]))
    back(change)
  end

  def destroy
    change = @deck.remove_card(Card.find(params[:card_id]))
    back(change)
  end

  private

  def set_deck
    @deck = current_player.decks.find(params[:id])
  end

  # Back to the builder with the same filters and page; a refused change explains itself.
  def back(change)
    flash = change.ok? ? {} : { danger: change.message }
    redirect_back fallback_location: deck_path(@deck), flash: flash
  end
end
