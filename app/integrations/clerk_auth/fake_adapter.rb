module ClerkAuth
  # In-memory stand-in for Clerk used by the test suite and for running the app locally without
  # a Clerk account. The browser side is served by vendor/fake_clerk/clerk.js, which implements
  # the subset of the clerk-js API the app uses (load, mountSignIn/Up, signOut, session.getToken).
  #
  # Tokens are trivially forgeable - the app refuses to boot with it in production.
  class FakeAdapter
    TOKEN_PREFIX = "fake-clerk.".freeze
    USER_ID_FORMAT = /\Auser_[A-Za-z0-9]{6,64}\z/
    WEBHOOK_SECRET = "whsec_#{Base64.strict_encode64('fake-clerk-webhook-signing-secret')}".freeze

    def self.token_for(user_id) = "#{TOKEN_PREFIX}#{user_id}"

    def fake? = true
    def publishable_key = "pk_test_fake"
    def frontend_script_url = "/__fake_clerk/clerk.js"
    def ui_script_url = nil

    def verify_session_token(token)
      raise InvalidToken, "missing session token" if token.blank?

      user_id = token.to_s.delete_prefix(TOKEN_PREFIX)
      raise InvalidToken, "not a fake clerk token" unless token.to_s.start_with?(TOKEN_PREFIX) && user_id.match?(USER_ID_FORMAT)

      Session.new(user_id: user_id, session_id: "sess_fake_#{user_id.delete_prefix('user_')}", claims: { "sub" => user_id }.freeze)
    end

    def verify_webhook!(payload:, headers:)
      webhook_verifier.verify!(payload: payload, headers: headers)
    end

    def webhook_verifier = WebhookVerifier.new(WEBHOOK_SECRET)
  end
end
