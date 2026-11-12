module ClerkAuth
  class Adapter
    BACKEND_API_URL = "https://api.clerk.com/v1".freeze
    JWKS_CACHE_TTL = 1.hour
    JWKS_FORCED_REFRESH_INTERVAL = 1.minute
    ALGORITHMS = %w[RS256].freeze

    attr_reader :publishable_key

    def initialize(publishable_key:, secret_key: nil, jwt_key: nil, authorized_parties: [], webhook_secret: nil,
                   leeway: 5, cache: Rails.cache, faraday_adapter: Faraday.default_adapter, clerk_js_version: ENV.fetch("CLERK_JS_VERSION", "6"),
                   clerk_ui_version: ENV.fetch("CLERK_UI_VERSION", "1"))
      @publishable_key = publishable_key
      @secret_key = secret_key.presence
      @jwt_key = jwt_key.presence && OpenSSL::PKey::RSA.new(jwt_key.gsub('\n', "\n"))
      @authorized_parties = Array(authorized_parties)
      @webhook_verifier = webhook_secret.present? ? WebhookVerifier.new(webhook_secret) : nil
      @leeway = leeway
      @cache = cache
      @faraday_adapter = faraday_adapter
      @clerk_js_version = clerk_js_version
      @clerk_ui_version = clerk_ui_version
      @last_forced_refresh_at = Concurrent::AtomicReference.new(Time.at(0))
      frontend_api_host # validates the publishable key eagerly
    end

    def fake? = false

    # pk_test_<base64("<frontend api host>$")>
    def frontend_api_host
      @frontend_api_host ||= begin
        encoded = publishable_key.to_s.split("_", 3).last
        host = Base64.decode64(encoded.to_s).delete_suffix("$")
        raise ArgumentError, "invalid Clerk publishable key" unless host.match?(/\A[a-z0-9.-]+\z/i)

        host
      end
    end

    def frontend_script_url
      "https://#{frontend_api_host}/npm/@clerk/clerk-js@#{@clerk_js_version}/dist/clerk.browser.js"
    end

    # Clerk Core 3 ships the prebuilt components (<SignIn/>, <SignUp/>, <UserButton/>) as a
    # separate bundle that is handed to Clerk.load({ ui: { ClerkUI } }).
    def ui_script_url
      "https://#{frontend_api_host}/npm/@clerk/ui@#{@clerk_ui_version}/dist/ui.browser.js"
    end

    # Returns a ClerkAuth::Session or raises InvalidToken / ConnectionError.
    def verify_session_token(token)
      raise InvalidToken, "missing session token" if token.blank?

      claims, _header = JWT.decode(token, @jwt_key, true, decode_options)
      verify_authorized_party!(claims)
      raise InvalidToken, "token has no subject" if claims["sub"].blank?

      Session.new(user_id: claims["sub"], session_id: claims["sid"], claims: claims.freeze)
    rescue JWT::DecodeError => e
      raise InvalidToken, "#{e.class.name.demodulize}: #{e.message}"
    end

    def verify_webhook!(payload:, headers:)
      raise InvalidWebhook, "CLERK_WEBHOOK_SIGNING_SECRET is not configured" unless @webhook_verifier

      @webhook_verifier.verify!(payload: payload, headers: headers)
    end

    def inspect = "#<#{self.class.name} frontend_api=#{frontend_api_host}>"

    private

    def decode_options
      options = { algorithms: ALGORITHMS, leeway: @leeway, verify_expiration: true, verify_not_before: true, required_claims: %w[sub exp] }
      options[:jwks] = method(:load_jwks) unless @jwt_key
      options
    end

    def verify_authorized_party!(claims)
      return if @authorized_parties.empty? || claims["azp"].blank?
      return if @authorized_parties.include?(claims["azp"])

      raise InvalidToken, "unauthorized party #{claims['azp'].inspect}"
    end

    # JWT gem JWKS loader. Called again with kid_not_found: true when the token's kid is unknown
    # (key rotation) - we then refetch, but at most once per JWKS_FORCED_REFRESH_INTERVAL so
    # garbage tokens with random kids cannot be used to hammer Clerk.
    def load_jwks(options = {})
      force = options[:kid_not_found] || options[:invalidate]
      force &&= throttle_forced_refresh
      @cache.fetch(jwks_cache_key, expires_in: JWKS_CACHE_TTL, force: force) { fetch_jwks }
    end

    def throttle_forced_refresh
      now = Time.current
      last = @last_forced_refresh_at.get
      return false if now - last < JWKS_FORCED_REFRESH_INTERVAL

      @last_forced_refresh_at.compare_and_set(last, now)
    end

    def jwks_cache_key = "clerk_auth/jwks/#{frontend_api_host}"

    def fetch_jwks
      response =
        if @secret_key
          http.get("#{BACKEND_API_URL}/jwks", nil, "Authorization" => "Bearer #{@secret_key}")
        else
          http.get("https://#{frontend_api_host}/.well-known/jwks.json")
        end
      raise ConnectionError, "Clerk JWKS request failed (HTTP #{response.status})" unless response.success?

      jwks = JSON.parse(response.body)
      raise ConnectionError, "Clerk JWKS response has no keys" unless jwks["keys"].is_a?(Array)

      jwks.deep_symbolize_keys
    rescue Faraday::Error => e
      raise ConnectionError, "Clerk JWKS unreachable: #{e.message}"
    rescue JSON::ParserError
      raise ConnectionError, "Clerk JWKS response is not JSON"
    end

    def http
      @http ||= Faraday.new(request: { open_timeout: 3, timeout: 5 }) do |faraday|
        faraday.request :retry, max: 2, interval: 0.2, backoff_factor: 2, retry_statuses: [ 429, 500, 502, 503, 504 ]
        faraday.adapter @faraday_adapter
      end
    end
  end
end
