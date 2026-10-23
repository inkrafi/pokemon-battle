module GamesHelper
  # A button that plays one move. It carries the version of the board the page was drawn from.
  # Moves are sent in the background (remote) and Turbolinks draws the board again, so the page,
  # its sound and music stay loaded from one move to the next.
  def game_action(board, label, params, **html)
    button_to label, actions_game_path(board.game), html.merge(params: params.merge(version: board.version), form: { data: { remote: true } })
  end

  # The same, for a button whose content is more than text (symbols and a name).
  def game_action_with(board, params, **html, &block)
    button_to actions_game_path(board.game), html.merge(params: params.merge(version: board.version), form: { data: { remote: true } }), &block
  end

  # Energy symbols for the Energy attached to a Pokémon, or a word when there is none.
  def attached_energy(cards)
    return content_tag(:span, 'No Energy', class: 'slot__none') if cards.empty?

    safe_join(cards.map { |card| energy_icon(card.type || 'Colorless', size: :sm) })
  end

  # A card's picture that opens it large in the card viewer (games/_card_zoom), so its text can be read.
  # A card without a picture (the basic Energy) shows its type and name, and opens the card page.
  def card_thumb(card, size: :md)
    type = card.type || 'Colorless'
    html = { class: ['card-thumb', "card-thumb--#{size}"], data: { type: type.parameterize } }

    unless card.image_url.present?
      html[:class] << 'card-thumb--plain'
      return link_to(card_path(card), html.merge(target: '_blank', rel: 'noopener')) do
        safe_join([energy_icon(type, size: :lg), content_tag(:span, card.name, class: 'card-thumb__name')])
      end
    end

    picture = image_tag("#{card.image_url}/low.webp", alt: '', width: 245, height: 337, loading: 'lazy', decoding: 'async')
    button_tag picture, html.deep_merge(type: 'button', title: card.name, aria: { label: "Show #{card.name} larger" },
                                        data: { card_zoom: "#{card.image_url}/high.webp", card_name: card.name, card_url: card_path(card) })
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
