module ReadModels
  class EventVoteTally
    # Projects voting facts into per-event counters.
    #
    # Async (own queue) so the write path stays fast and a slow/broken projection never blocks
    # voting. Idempotent (ProcessedFact ledger in the same transaction) because async delivery
    # is at-least-once, and order-independent because it only applies commutative deltas.
    class Projector
      include Handler.async(queue: "read_models")
      subscribes_to(*Voting::FACTS)

      def self.delta_for(fact)
        up = down = 0
        case fact
        when Voting::EventUpvoted then up += 1
        when Voting::EventDownvoted then down += 1
        end

        case fact.data[:previous_vote]
        when "up" then up -= 1
        when "down" then down -= 1
        end
        [ up, down ]
      end

      def call(fact)
        EventVoteTally.transaction do
          next unless ProcessedFact.claim(handler: self.class.name, event_id: fact.event_id)

          up, down = self.class.delta_for(fact)
          EventVoteTally.apply_delta!(event_tid: fact.data.fetch(:event_tid), up: up, down: down)
        end
      end
    end
  end
end
