module Tcgdex
  # Raised for a kind of card the app has no use for (stickers, tokens and the like).
  class UnsupportedCard < StandardError; end
end
