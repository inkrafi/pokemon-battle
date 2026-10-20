class StaticPagesController < ApplicationController
  def home
    @featured = Card.playable.pokemon.where.not(subtype: 'stage2').includes(:card_set).order(Arel.sql('RANDOM()')).limit(3).to_a
  end

  def about
  end
end
