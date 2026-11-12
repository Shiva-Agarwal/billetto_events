module ClerkAuth
  # Verifies Svix-signed webhooks as sent by Clerk (https://docs.svix.com/receiving/verifying-payloads/how-manual):
  #   signature = base64(HMAC-SHA256(secret, "#{svix-id}.#{svix-timestamp}.#{raw body}"))
  # The timestamp tolerance protects against replay attacks.
  class WebhookVerifier
    TOLERANCE = 5.minutes

    def initialize(secret, clock: -> { Time.current })
      @secret = Base64.decode64(secret.to_s.delete_prefix("whsec_"))
      raise ArgumentError, "webhook secret is empty" if @secret.empty?

      @clock = clock
    end

    def verify!(payload:, headers:)
      id = headers["svix-id"].presence
      timestamp = headers["svix-timestamp"].presence
      signatures = headers["svix-signature"].presence
      raise InvalidWebhook, "missing svix headers" unless id && timestamp && signatures
      raise InvalidWebhook, "timestamp outside tolerance" if (@clock.call.to_i - timestamp.to_i).abs > TOLERANCE

      expected = sign(id, timestamp, payload)
      valid = signatures.split(" ").any? do |entry|
        version, signature = entry.split(",", 2)
        version == "v1" && ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
      end
      raise InvalidWebhook, "invalid signature" unless valid

      JSON.parse(payload)
    rescue JSON::ParserError
      raise InvalidWebhook, "payload is not JSON"
    end

    def sign(id, timestamp, payload)
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @secret, "#{id}.#{timestamp}.#{payload}"))
    end
  end
end
