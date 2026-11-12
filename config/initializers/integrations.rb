# Anti-corruption layer adapters for 3rd party systems (see app/integrations).
# The test environment (and development without credentials) uses in-memory fakes,
# so the suite never stubs raw HTTP for business-level tests (Developer's Guide).
if Rails.env.production? && (Rails.configuration.x.fake_billetto || Rails.configuration.x.fake_clerk)
  raise "Fake integrations must never be enabled in production (fake Clerk tokens are forgeable)"
end

Rails.configuration.to_prepare do
  Rails.configuration.billetto =
    if Rails.configuration.x.fake_billetto
      Billetto::FakeAdapter.with_sample_events
    else
      Billetto::Adapter.new(
        api_keypair: ENV.fetch("BILLETTO_API_KEYPAIR"),
        base_url: ENV.fetch("BILLETTO_API_BASE_URL", Billetto::Adapter::DEFAULT_BASE_URL)
      )
    end

  Rails.configuration.clerk =
    if Rails.configuration.x.fake_clerk
      ClerkAuth::FakeAdapter.new
    else
      ClerkAuth::Adapter.new(
        publishable_key: ENV.fetch("CLERK_PUBLISHABLE_KEY"),
        secret_key: ENV["CLERK_SECRET_KEY"],
        jwt_key: ENV["CLERK_JWT_KEY"],
        authorized_parties: ENV.fetch("CLERK_AUTHORIZED_PARTIES", "").split(",").map(&:strip).reject(&:empty?),
        webhook_secret: ENV["CLERK_WEBHOOK_SIGNING_SECRET"]
      )
    end
end
