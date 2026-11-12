module Billetto
  # Pulls Billetto public events page by page and hands each page to the Catalog.
  #
  # Each page is imported by its own command (= its own short transaction), so a failure on
  # page 37 does not roll back pages 1-36, locks are held briefly, and memory stays flat
  # regardless of how many events Billetto returns. Re-running is idempotent.
  #
  # Schedule it (cron / sidekiq-cron / Solid Queue recurring) or run `bin/rails billetto:sync`.
  class SyncPublicEventsJob < ApplicationJob
    queue_as :low

    retry_on(*Billetto::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5)
    discard_on Billetto::AuthenticationError do |_job, error|
      Rails.logger.error("[billetto.sync] discarded: #{error.message}")
    end

    def perform(max_pages: nil, page_size: 50)
      totals = { pages: 0, imported: 0, updated: 0, unchanged: 0, rejected: 0 }

      adapter.each_page(page_size: page_size, max_pages: max_pages) do |page|
        result = command_bus.call(Catalog::ImportEvents.new(source: "billetto", events: page.records))
        totals[:pages] += 1
        result.to_h.each { |key, count| totals[key] += count }
        totals[:rejected] += page.rejections.size
        page.rejections.each { |rejection| Rails.logger.warn("[billetto.sync] rejected #{rejection.inspect}") }
      end

      event_store.publish(Billetto::PublicEventsSynced.strict(data: totals))
      totals
    end

    private

    def adapter = Rails.configuration.billetto
  end
end
