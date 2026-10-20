module ApplicationHelper
  # Simple original glyphs for the ten Energy types (24x24 viewBox). They stand in for the
  # official Energy symbols, which are artwork this app doesn't reproduce.
  ENERGY_PATHS = {
    'Grass'     => 'M12 3C6 6 4 12 5 20c7 0 13-4 14-14-2-1-4-2-7-3z',
    'Fire'      => 'M12 2c1 4 5 6 5 11a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-4 0-7 1-10z',
    'Water'     => 'M12 2C9 7 6 10 6 14a6 6 0 0 0 12 0c0-4-3-7-6-12z',
    'Lightning' => 'M13 2 5 14h6l-1 8 8-12h-6z',
    'Psychic'   => 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zm10-3a3 3 0 1 0 0 6 3 3 0 0 0 0-6z',
    'Fighting'  => 'M6 8h12v8a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4zm2-3h2v3H8zm3 0h2v3h-2zm3 0h2v3h-2z',
    'Darkness'  => 'M20 14A8 8 0 1 1 10 4a6 6 0 0 0 10 10z',
    'Metal'     => 'M12 2l8 5v10l-8 5-8-5V7zm0 6a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
    'Dragon'    => 'M12 2l9 10-9 10L3 12z',
    'Colorless' => 'M12 2l2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z'
  }.freeze

  # A round Energy symbol. The type is also the title, so it never relies on color alone.
  def energy_icon(type, size: :md)
    name = ENERGY_PATHS.key?(type) ? type : 'Colorless'

    content_tag(:span, class: ['energy', "energy--#{size}"], data: { type: name.downcase }, title: name, role: 'img', aria: { label: name }) do
      tag.svg(tag.path(d: ENERGY_PATHS[name], fill_rule: 'evenodd'), viewBox: '0 0 24 24', aria: { hidden: true }, focusable: 'false')
    end
  end

  # A row of Energy symbols, such as an attack cost or a retreat cost.
  def energy_cost(types, size: :sm)
    safe_join(Array(types).map { |type| energy_icon(type, size: size) })
  end

  # "60", "60+", "30×" or "" for an attack that deals no damage of its own.
  def damage_text(attack)
    attack['damage'] ? "#{attack['damage']}#{attack['modifier']}" : ''
  end

  def nav_link(label, path, active)
    link_to label, path, class: ['nav-link', ('active' if active)].compact, aria: { current: (active ? 'page' : nil) }
  end

  # In development Sprockets and Webpacker re-check every asset file on every call, which adds
  # several hundred milliseconds per page on a Docker bind mount. The tags are cached here and
  # rebuilt only when a source file changes (a handful of stat calls instead of a full check).
  DEV_ASSET_TAGS = Concurrent::Map.new

  def app_stylesheet_tag
    options = { media: 'all', 'data-turbolinks-track': 'reload' }
    return stylesheet_link_tag('application', **options) unless Rails.env.development?

    files = Dir[Rails.root.join('app/assets/{stylesheets,images,fonts}/**/*').to_s]
    DEV_ASSET_TAGS.fetch_or_store(['css', files.map { |file| File.mtime(file).to_f }.max]) do
      stylesheet_link_tag('application', **options)
    end
  end

  # (named app_* so it does not shadow Rails' own javascript_tag helper)
  def app_javascript_tag
    options = { 'data-turbolinks-track': 'reload' }
    manifest = Rails.root.join('public/packs/manifest.json')
    # With on-demand compiling (no watcher) Webpacker has to see every request, so don't cache.
    return javascript_pack_tag('application', **options) unless Rails.env.development? && !Webpacker.config.compile? && manifest.exist?

    DEV_ASSET_TAGS.fetch_or_store(['js', manifest.mtime.to_f]) { javascript_pack_tag('application', **options) }
  end
end
