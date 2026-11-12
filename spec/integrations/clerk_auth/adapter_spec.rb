require "rails_helper"

RSpec.describe ClerkAuth::Adapter do
  let(:frontend_api) { "clerk.example.accounts.dev" }
  let(:publishable_key) { "pk_test_#{Base64.strict_encode64("#{frontend_api}$")}" }
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(rsa_key, kid: "ins_test_key") }
  let(:jwks_url) { "https://#{frontend_api}/.well-known/jwks.json" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:authorized_parties) { [ "http://localhost:3000" ] }

  subject(:adapter) do
    described_class.new(publishable_key: publishable_key, authorized_parties: authorized_parties, cache: cache)
  end

  before { stub_request(:get, jwks_url).to_return(status: 200, body: { keys: [ jwk.export ] }.to_json) }

  def token(key: rsa_key, kid: "ins_test_key", algorithm: "RS256", **claims)
    now = Time.current.to_i
    payload = { sub: "user_2abc", sid: "sess_123", azp: "http://localhost:3000", iat: now, nbf: now - 5, exp: now + 60 }.merge(claims)
    JWT.encode(payload.compact, key, algorithm, { kid: kid })
  end

  it "verifies a valid session token and returns the session" do
    session = adapter.verify_session_token(token)

    expect(session).to have_attributes(user_id: "user_2abc", session_id: "sess_123")
  end

  it "caches the JWKS between verifications" do
    2.times { adapter.verify_session_token(token) }

    expect(a_request(:get, jwks_url)).to have_been_made.once
  end

  it "rejects expired, not-yet-valid, foreign-signed and tampered tokens" do
    expect { adapter.verify_session_token(token(exp: 1.minute.ago.to_i)) }.to raise_error(ClerkAuth::InvalidToken, /expired/i)
    expect { adapter.verify_session_token(token(nbf: 1.minute.from_now.to_i)) }.to raise_error(ClerkAuth::InvalidToken)
    expect { adapter.verify_session_token(token(key: OpenSSL::PKey::RSA.generate(2048))) }.to raise_error(ClerkAuth::InvalidToken)
    expect { adapter.verify_session_token("#{token}x") }.to raise_error(ClerkAuth::InvalidToken)
    expect { adapter.verify_session_token("") }.to raise_error(ClerkAuth::InvalidToken)
  end

  it "rejects algorithm confusion (HS256 signed with a public value)" do
    expect { adapter.verify_session_token(token(key: "secret", algorithm: "HS256")) }.to raise_error(ClerkAuth::InvalidToken)
  end

  it "rejects tokens issued for an unauthorized party" do
    expect { adapter.verify_session_token(token(azp: "https://evil.example")) }
      .to raise_error(ClerkAuth::InvalidToken, /unauthorized party/)
  end

  it "rejects tokens without a subject" do
    expect { adapter.verify_session_token(token(sub: nil)) }.to raise_error(ClerkAuth::InvalidToken)
  end

  it "refetches the JWKS once when it sees an unknown key id (key rotation)" do
    adapter.verify_session_token(token) # warm cache
    rotated = OpenSSL::PKey::RSA.generate(2048)
    rotated_jwk = JWT::JWK.new(rotated, kid: "ins_rotated")
    stub_request(:get, jwks_url).to_return(status: 200, body: { keys: [ jwk.export, rotated_jwk.export ] }.to_json)

    expect(adapter.verify_session_token(token(key: rotated, kid: "ins_rotated")).user_id).to eq("user_2abc")
  end

  it "verifies networklessly with CLERK_JWT_KEY" do
    networkless = described_class.new(publishable_key: publishable_key, jwt_key: rsa_key.public_key.to_pem, cache: cache)

    expect(networkless.verify_session_token(token).user_id).to eq("user_2abc")
    expect(a_request(:get, jwks_url)).not_to have_been_made
  end

  it "uses the Backend API JWKS endpoint when a secret key is configured" do
    backend = stub_request(:get, "https://api.clerk.com/v1/jwks")
      .with(headers: { "Authorization" => "Bearer sk_test_123" })
      .to_return(status: 200, body: { keys: [ jwk.export ] }.to_json)
    with_secret = described_class.new(publishable_key: publishable_key, secret_key: "sk_test_123", cache: cache)

    expect(with_secret.verify_session_token(token).user_id).to eq("user_2abc")
    expect(backend).to have_been_requested
  end

  it "raises ConnectionError when the JWKS cannot be fetched" do
    stub_request(:get, jwks_url).to_return(status: 500)

    expect { adapter.verify_session_token(token) }.to raise_error(ClerkAuth::ConnectionError)
  end

  it "derives the clerk-js and Clerk UI bundle URLs from the publishable key" do
    expect(adapter.frontend_script_url).to eq("https://#{frontend_api}/npm/@clerk/clerk-js@6/dist/clerk.browser.js")
    expect(adapter.ui_script_url).to eq("https://#{frontend_api}/npm/@clerk/ui@1/dist/ui.browser.js")
  end
end
