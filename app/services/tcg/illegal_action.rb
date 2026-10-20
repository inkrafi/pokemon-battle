module Tcg
  # Raised when a player tries something the rules don't allow. The message says why.
  class IllegalAction < StandardError; end
end
