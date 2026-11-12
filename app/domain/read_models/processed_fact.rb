module ReadModels
  # Idempotency ledger for at-least-once async handlers.
  class ProcessedFact < ApplicationRecord
    self.table_name = "processed_facts"

    # Atomically records that `handler` processed `event_id`. Returns false when it already did
    # (INSERT ... ON CONFLICT DO NOTHING), so duplicate deliveries become no-ops.
    def self.claim(handler:, event_id:)
      insert_all(
        [ { handler: handler, event_id: event_id, created_at: Time.current } ],
        unique_by: %i[handler event_id],
        returning: %i[id]
      ).rows.any?
    end
  end
end
