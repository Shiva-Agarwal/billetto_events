# Anti-corruption layer for the Billetto public API
# (https://api.billetto.com/reference/list-public-events).
#
# Nothing outside this module knows about Billetto's payloads or HTTP errors: the adapter
# translates API events into Catalog attribute hashes (Billetto::EventRecord) and raises only
# Billetto::Error subclasses, so 3rd party exceptions never bubble up into the domain.
module Billetto
  Error = Class.new(StandardError)
  ConnectionError = Class.new(Error)      # timeouts, DNS, TLS, connection resets (retryable)
  ServerError = Class.new(Error)          # 5xx after retries (retryable)
  RateLimitedError = Class.new(Error)     # 429 after retries (retryable)
  AuthenticationError = Class.new(Error)  # 401/403 - wrong keypair (not retryable)
  ClientError = Class.new(Error)          # other 4xx (not retryable)
  InvalidResponseError = Class.new(Error) # unparsable / unexpected payload

  RETRYABLE_ERRORS = [ ConnectionError, ServerError, RateLimitedError ].freeze

  # Published after every sync run: audit trail + something to alert on.
  class PublicEventsSynced < Fact
    SCHEMA = {
      pages: Integer,
      imported: Integer,
      updated: Integer,
      unchanged: Integer,
      rejected: Integer
    }.freeze

    def stream_names = [ "Billetto::PublicEventsSync" ]
  end

  # One page of the public events listing, already translated.
  Page = Data.define(:records, :rejections, :has_more, :next_url) do
    def self.from_api(body)
      unless body.is_a?(Hash) && body["data"].is_a?(Array)
        raise InvalidResponseError, "expected an object with a `data` array"
      end

      records = []
      rejections = []
      body["data"].each do |payload|
        records << EventRecord.from_api(payload)
      rescue EventRecord::Invalid => e
        rejections << { external_id: payload.is_a?(Hash) ? payload["id"].to_s : nil, reason: e.message }
      end

      new(records: records, rejections: rejections, has_more: body["has_more"] == true, next_url: body["next_url"].presence)
    end
  end

  def self.subscriptions
    [].map(&:subscriptions).reduce({}, :merge)
  end
end
