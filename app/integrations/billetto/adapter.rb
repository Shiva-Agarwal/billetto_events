module Billetto
  # HTTP adapter for the Billetto public events API.
  #
  #   adapter.each_page(page_size: 100, max_pages: 10) { |page| ... }
  #
  # * Auth: `Api-Keypair: <key id>:<secret>` header.
  # * Pagination: cursor based; follows `next_url` while `has_more` - only on the configured
  #   API host, so the keypair can never be sent to another host.
  # * Resilience: connect/read timeouts, retries with exponential backoff + jitter for
  #   timeouts, 429 (honouring Retry-After) and 5xx; everything else is mapped to Billetto::Error.
  class Adapter
    DEFAULT_BASE_URL = "https://billetto.dk/api/v3".freeze
    PUBLIC_EVENTS_PATH = "public/events".freeze
    MAX_PAGE_SIZE = 100
    RETRY_STATUSES = [ 429, 500, 502, 503, 504 ].freeze

    def initialize(api_keypair:, base_url: DEFAULT_BASE_URL, open_timeout: 5, timeout: 20,
                   max_retries: 3, retry_interval: 0.5, faraday_adapter: Faraday.default_adapter)
      raise ArgumentError, "Billetto api_keypair must look like '<key id>:<secret>'" unless api_keypair.to_s.include?(":")

      @api_keypair = api_keypair
      @base_uri = URI.parse(base_url.to_s.chomp("/") + "/")
      @open_timeout = open_timeout
      @timeout = timeout
      @max_retries = max_retries
      @retry_interval = retry_interval
      @faraday_adapter = faraday_adapter
    end

    def list_public_events(limit: 50, after: nil)
      params = { limit: limit.to_i.clamp(1, MAX_PAGE_SIZE), after: after }.compact
      Page.from_api(get(PUBLIC_EVENTS_PATH, params))
    end

    def each_page(page_size: 50, max_pages: nil)
      return enum_for(:each_page, page_size: page_size, max_pages: max_pages) unless block_given?

      page = list_public_events(limit: page_size)
      fetched = 1
      loop do
        yield page
        break unless page.has_more && page.next_url
        break if max_pages && fetched >= max_pages

        page = Page.from_api(get(trusted_next_url(page.next_url)))
        fetched += 1
      end
    end

    def inspect = "#<#{self.class.name} base_url=#{@base_uri}>" # never leak the keypair

    private

    def get(path_or_url, params = {})
      handle_response(connection.get(path_or_url, params))
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
      raise ConnectionError, "Billetto API unreachable: #{e.class.name.demodulize} #{e.message}"
    end

    def handle_response(response)
      case response.status
      when 200..299 then parse_json(response.body)
      when 401, 403 then raise AuthenticationError, "Billetto API rejected the keypair (HTTP #{response.status})"
      when 429 then raise RateLimitedError, "Billetto API rate limit exceeded"
      when 400..499 then raise ClientError, "Billetto API request failed (HTTP #{response.status}): #{response.body.to_s.truncate(200)}"
      else raise ServerError, "Billetto API error (HTTP #{response.status})"
      end
    end

    def parse_json(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError => e
      raise InvalidResponseError, "Billetto API returned invalid JSON: #{e.message.truncate(100)}"
    end

    def trusted_next_url(next_url)
      uri = URI.parse(next_url)
      uri = @base_uri.merge(uri) if uri.relative?
      unless uri.host == @base_uri.host && uri.scheme == @base_uri.scheme
        raise InvalidResponseError, "refusing to follow next_url to untrusted host #{uri.host.inspect}"
      end

      uri.to_s
    rescue URI::InvalidURIError
      raise InvalidResponseError, "invalid next_url #{next_url.inspect}"
    end

    def connection
      @connection ||= Faraday.new(
        url: @base_uri.to_s,
        headers: {
          "Api-Keypair" => @api_keypair,
          "Accept" => "application/json",
          "User-Agent" => "BillettoEvents/1.0 (+Rails #{Rails.version})"
        },
        request: { open_timeout: @open_timeout, timeout: @timeout }
      ) do |faraday|
        faraday.request :retry,
          max: @max_retries,
          interval: @retry_interval,
          interval_randomness: 0.5,
          backoff_factor: 2,
          methods: %i[get],
          retry_statuses: RETRY_STATUSES,
          exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::RetriableResponse, Errno::ECONNRESET ]
        faraday.adapter @faraday_adapter
      end
    end
  end
end
