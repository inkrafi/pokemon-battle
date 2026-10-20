class CardsController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @sets = CardSet.order(:name)
    @cards = filtered_cards.order(:name, :tcgdex_id).page(params[:page]).per(24)
  end

  def show
    @card = Card.includes(:card_set).find(params[:id])
    @decks = existing_player&.decks&.order(:name)
  end

  private

  def filtered_cards
    cards = Card.includes(:card_set)
    cards = cards.named_like(@query) if @query.present?
    cards = cards.where(supertype: params[:supertype]) if Card::SUPERTYPES.include?(params[:supertype])
    cards = cards.of_type(params[:type]) if Card::TYPES.include?(params[:type])
    cards = cards.where(card_set_id: params[:set]) if params[:set].present?
    cards = cards.playable if params[:playable] == '1'
    cards
  end
end
