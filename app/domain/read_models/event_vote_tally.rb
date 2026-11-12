module ReadModels
  class EventVoteTally < ApplicationRecord
    self.table_name = "event_vote_tallies"

    INCREMENT_SQL = Arel.sql(<<~SQL.squish)
      upvotes = event_vote_tallies.upvotes + EXCLUDED.upvotes,
      downvotes = event_vote_tallies.downvotes + EXCLUDED.downvotes,
      updated_at = EXCLUDED.updated_at
    SQL

    def score = upvotes - downvotes
    def total = upvotes + downvotes

    # Atomic, lock-free (single statement) counter update - no read-modify-write race even with
    # many workers projecting votes for the same event concurrently.
    def self.apply_delta!(event_tid:, up:, down:)
      return if up.zero? && down.zero?

      upsert({ event_tid: event_tid, upvotes: up, downvotes: down },
        unique_by: :event_tid, on_duplicate: INCREMENT_SQL, record_timestamps: true)
    end

    # Rebuilds all tallies from the event log. Deltas are commutative, so the result does not
    # depend on fact ordering. Run while projections are paused (or into a shadow table).
    def self.rebuild!(event_store: Rails.configuration.event_store, batch_size: 1_000)
      handler = Projector.name
      transaction do
        delete_all
        ProcessedFact.where(handler: handler).delete_all

        totals = Hash.new { |hash, key| hash[key] = [ 0, 0 ] }
        event_store.read.of_type(Voting::FACTS).in_batches(batch_size).each_batch do |facts|
          facts.each do |fact|
            up, down = Projector.delta_for(fact)
            totals[fact.data.fetch(:event_tid)][0] += up
            totals[fact.data.fetch(:event_tid)][1] += down
          end
          now = Time.current
          ProcessedFact.insert_all(facts.map { |fact| { handler: handler, event_id: fact.event_id, created_at: now } })
        end

        totals.each_slice(batch_size) do |slice|
          insert_all(slice.map { |event_tid, (up, down)| { event_tid: event_tid, upvotes: up, downvotes: down } })
        end
        totals.size
      end
    end
  end
end
