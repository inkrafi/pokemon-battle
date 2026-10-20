module GamesHelper
  # A button that plays one move. It carries the version of the board the page was drawn from.
  def game_action(board, label, params, **html)
    button_to label, actions_game_path(board.game), html.merge(params: params.merge(version: board.version))
  end

  # The same, for a button whose content is more than text (symbols and a name).
  def game_action_with(board, params, **html, &block)
    button_to actions_game_path(board.game), html.merge(params: params.merge(version: board.version)), &block
  end

  # Energy symbols for the Energy attached to a Pokémon, or a word when there is none.
  def attached_energy(cards)
    return content_tag(:span, 'No Energy', class: 'slot__none') if cards.empty?

    safe_join(cards.map { |card| energy_icon(card.type || 'Colorless', size: :sm) })
  end

  def mode_label(game)
    return 'Against the computer' if game.bot?
    return 'Online, against a friend' if game.online?

    'Two players, one screen'
  end

  # Deck choices for a select: the sample decks, then the guest's own.
  def deck_options(decks, selected = nil)
    samples, own = decks.partition(&:sample?)
    groups = []
    groups << ['Sample decks', samples.map { |deck| [deck.name, deck.id] }] if samples.any?
    groups << ['Your decks', own.map { |deck| [deck.name, deck.id] }] if own.any?
    grouped_options_for_select(groups, selected)
  end
end
