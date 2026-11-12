module Catalog
  class Service
    include Command::Handler

    handles ImportEvents, :import_events

    IMPORTABLE_ATTRIBUTES = %i[
      external_id title description starts_at ends_at url image_url venue_name city
      country_code organiser_name min_price_cents currency raw_payload
    ].freeze
    UPSERT_COLUMNS = (%w[tid source last_synced_at content_digest] + IMPORTABLE_ATTRIBUTES.map(&:to_s)).freeze
    UPDATE_COLUMNS = (UPSERT_COLUMNS - %w[tid source external_id]).freeze

    Result = Data.define(:imported, :updated, :unchanged, :rejected) do
      def to_h = { imported: imported.size, updated: updated.size, unchanged: unchanged.size, rejected: rejected.size }
    end

    def initialize(clock: -> { Time.current })
      @clock = clock
    end

    private

    # Idempotent, set-based ingestion of a batch:
    #   1 SELECT for existing digests, 1 upsert for new+changed rows, 1 UPDATE for unchanged
    #   rows - independent of batch size. Facts are only published for real changes, so
    #   re-running a sync is cheap and does not flood the event store.
    def import_events(cmd)
      now = @clock.call
      serialize_imports_for(cmd.source)

      candidates = cmd.events.map { |attrs| build_event(cmd.source, attrs, now) }
      valid, invalid = candidates.partition { |event| event.valid?(:import) }
      valid = valid.index_by(&:external_id).values # last occurrence wins within a batch

      existing = existing_events(cmd.source, valid.map(&:external_id))
      new_events, known = valid.partition { |event| !existing.key?(event.external_id) }
      changed, unchanged = known.partition { |event| existing.dig(event.external_id, :digest) != event.content_digest }
      changed.each { |event| event.tid = existing.dig(event.external_id, :tid) }

      upsert(new_events + changed)
      touch_synced(cmd.source, unchanged, now)
      publish_imported(new_events)
      publish_changed(changed)

      Result.new(imported: new_events, updated: changed, unchanged: unchanged, rejected: invalid).tap do |result|
        ActiveSupport::Notifications.instrument("import.catalog", source: cmd.source, **result.to_h,
          rejections: invalid.map { |event| { external_id: event.external_id, errors: event.errors.full_messages } })
      end
    end

    def build_event(source, attrs, now)
      attrs = attrs.to_h.symbolize_keys.slice(*IMPORTABLE_ATTRIBUTES)
      Event.new(**attrs, source: source, last_synced_at: now)
    end

    def existing_events(source, external_ids)
      return {} if external_ids.empty?

      Event.where(source: source, external_id: external_ids)
           .pluck(:external_id, :tid, :content_digest)
           .to_h { |external_id, tid, digest| [ external_id, { tid: tid, digest: digest } ] }
    end

    def upsert(events)
      return if events.empty?

      rows = events.map { |event| event.attributes.slice(*UPSERT_COLUMNS) }
      Event.upsert_all(rows, unique_by: %i[source external_id], update_only: UPDATE_COLUMNS, record_timestamps: true)
    end

    def touch_synced(source, events, now)
      return if events.empty?

      Event.where(source: source, external_id: events.map(&:external_id)).update_all(last_synced_at: now)
    end

    def publish_imported(events)
      events.each do |event|
        event_store.publish(EventImported.strict(data: {
          tid: event.tid,
          source: event.source,
          external_id: event.external_id,
          title: event.title,
          starts_at: event.starts_at.utc.iso8601
        }))
      end
    end

    def publish_changed(events)
      events.each do |event|
        event_store.publish(EventDetailsChanged.strict(data: {
          tid: event.tid,
          source: event.source,
          external_id: event.external_id,
          content_digest: event.content_digest
        }))
      end
    end

    # Concurrent syncs of the same source (e.g. a cron overlapping a manual run) are serialized
    # with a transaction-scoped advisory lock, so the "is it new or changed?" decision is race free.
    def serialize_imports_for(source)
      sql = Event.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext(?))", "catalog_import:#{source}" ])
      Event.connection.execute(sql)
    end
  end
end
