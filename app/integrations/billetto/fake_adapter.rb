module Billetto
  # In-memory stand-in for Billetto::Adapter (test suite, and development without API keys).
  # Exposes the same public interface and returns the same value objects, built from
  # API-shaped payloads, so the translation layer is exercised too.
  class FakeAdapter
    attr_reader :payloads, :requests

    def self.with_sample_events(count: 12, now: Time.current)
      new(SampleEvents.build(count: count, now: now))
    end

    def initialize(payloads = [], fail_with: nil)
      @payloads = payloads
      @fail_with = fail_with
      @requests = []
    end

    def fail_with!(error) = (@fail_with = error)

    def list_public_events(limit: 50, after: nil)
      @requests << { limit: limit, after: after }
      raise @fail_with if @fail_with

      start = after ? payloads.index { |p| p["id"].to_s == after.to_s }.to_i + 1 : 0
      slice = payloads[start, limit] || []
      has_more = start + limit < payloads.size
      Page.from_api(
        "object" => "list",
        "data" => slice,
        "has_more" => has_more,
        "next_url" => has_more ? "https://fake.billetto.test/api/v3/public/events?after=#{slice.last['id']}&limit=#{limit}" : nil
      )
    end

    def each_page(page_size: 50, max_pages: nil)
      return enum_for(:each_page, page_size: page_size, max_pages: max_pages) unless block_given?

      after = nil
      fetched = 0
      loop do
        page = list_public_events(limit: page_size, after: after)
        fetched += 1
        yield page
        break unless page.has_more
        break if max_pages && fetched >= max_pages

        after = Rack::Utils.parse_query(URI.parse(page.next_url).query)["after"]
      end
    end
  end
end
