# Cards. db/cards.json is a snapshot of the card database (see lib/tasks/cards.rake), so this
# works offline and can be run as often as you like.
snapshot = Rails.root.join('db', 'cards.json')
CardSnapshot.load(snapshot) if snapshot.exist?

# Two decks that are ready to play, for guests who don't want to build one first.
SampleDecks.create! if Card.playable.exists?
