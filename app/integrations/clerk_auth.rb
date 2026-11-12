# Anti-corruption layer for Clerk (https://clerk.com).
#
# * Browser side: Clerk's JS SDK (clerk-js) renders sign-up / sign-in / user button and manages
#   the session; it keeps a short-lived session JWT in the `__session` cookie.
# * Server side: ClerkAuth::Adapter verifies that JWT (RS256 signature against Clerk's JWKS,
#   exp/nbf, authorized party) - "networkless" after the JWKS is cached - and returns a
#   ClerkAuth::Session. Clerk webhooks (Svix signed) keep Identity::User in sync.
#
# Named ClerkAuth (not Clerk) so it can never clash with the official `clerk-sdk-ruby` gem.
module ClerkAuth
  Error = Class.new(StandardError)
  InvalidToken = Class.new(Error)
  ConnectionError = Class.new(Error)
  InvalidWebhook = Class.new(Error)

  SESSION_COOKIE = "__session".freeze

  Session = Data.define(:user_id, :session_id, :claims)

  def self.subscriptions
    [].map(&:subscriptions).reduce({}, :merge)
  end
end
