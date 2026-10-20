module Tcg
  # Plays legal moves more or less at random. It exists to exercise the rules (simulated games in
  # the tests and in rails tcg:simulate); a smarter opponent can replace it later.
  class RandomBot
    ATTACK_CHANCE = 0.85
    RETREAT_CHANCE = 0.1

    def initialize(rng: Random.new)
      @rng = rng
    end

    # The action +seat+ should play, or nil when it has nothing to do (not its turn).
    def choose(engine, seat)
      actions = engine.legal_actions(seat).reject { |action| action['type'] == 'concede' }
      return nil if actions.empty?

      by_type = actions.group_by { |action| action['type'] }
      %w[setup promote switch].each { |type| return pick(by_type[type]) if by_type[type] }
      return by_type['choose'].first if by_type['choose'] # the fullest search comes first

      return pick(by_type['attack']) if by_type['attack'] && @rng.rand < ATTACK_CHANCE

      building = actions.select { |action| %w[bench evolve attach play].include?(action['type']) }
      return pick(building) if building.any?
      return pick(by_type['retreat']) if by_type['retreat'] && @rng.rand < RETREAT_CHANCE

      by_type['end_turn'].first
    end

    # Plays both seats until the game ends or +max_actions+ is reached.
    def play_out(engine, max_actions: 5000)
      max_actions.times do
        return engine if engine.finished?

        seat = engine.seat_to_act
        engine.perform(seat, choose(engine, seat))
      end
      engine
    end

    private

    def pick(actions)
      actions[@rng.rand(actions.size)]
    end
  end
end
