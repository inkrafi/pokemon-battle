class DecksController < ApplicationController
  before_action :set_deck, only: [:show, :update, :destroy]

  def index
    @decks = current_player.decks.includes(deck_cards: :card).order(updated_at: :desc)
    @samples = Deck.samples.includes(deck_cards: :card)
  end

  # A copy of a sample deck (or one of your own) that you can change.
  def copy
    source = Deck.where(sample: true).or(Deck.where(player: current_player)).find(params[:id])
    copy = source.duplicate_for(current_player)
    redirect_to deck_path(copy), flash: { success: "#{copy.name} is in your decks." }
  end

  def new
    @deck = current_player.decks.new
  end

  def create
    @deck = current_player.decks.new(deck_params)

    if @deck.save
      redirect_to deck_path(@deck)
    else
      render 'new', status: :unprocessable_entity
    end
  end

  # The deck builder: the deck on one side, the cards that can be added on the other.
  def show
    @query = params[:q].to_s.strip
    @entries = @deck.deck_cards.includes(card: :card_set).sort_by { |entry| [entry.card.supertype, entry.card.name] }
    @problems = @deck.problems
    @pool = pool.order(:name, :tcgdex_id).page(params[:page]).per(12)
  end

  def update
    if @deck.update(deck_params)
      redirect_to deck_path(@deck), flash: { success: 'Deck renamed.' }
    else
      redirect_to deck_path(@deck), flash: { danger: @deck.errors.full_messages.to_sentence }
    end
  end

  def destroy
    @deck.destroy
    redirect_to decks_path, flash: { success: "Deck #{@deck.name} deleted." }
  end

  private

  def set_deck
    @deck = current_player.decks.find(params[:id])
  end

  def deck_params
    params.require(:deck).permit(:name)
  end

  def pool
    cards = Card.playable.standard.includes(:card_set)
    cards = cards.named_like(@query) if @query.present?
    cards = cards.where(supertype: params[:supertype]) if Card::SUPERTYPES.include?(params[:supertype])
    cards = cards.of_type(params[:type]) if Card::TYPES.include?(params[:type])
    cards
  end
end
