require "rails_helper"

RSpec.describe ClerkAuth::WebhookVerifier do
  subject(:verifier) { described_class.new(ClerkAuth::FakeAdapter::WEBHOOK_SECRET) }

  let(:payload) { { type: "user.created", data: { id: "user_123abc" } }.to_json }
  let(:timestamp) { Time.current.to_i.to_s }

  def headers(signature: verifier.sign("msg_1", timestamp, payload), ts: timestamp)
    { "svix-id" => "msg_1", "svix-timestamp" => ts, "svix-signature" => "v1,#{signature}" }
  end

  it "returns the parsed payload for a valid signature" do
    expect(verifier.verify!(payload: payload, headers: headers)).to include("type" => "user.created")
  end

  it "accepts any valid signature in a multi-signature header (secret rotation)" do
    rotated = headers.merge("svix-signature" => "v1,bm9wZQ== v1,#{verifier.sign('msg_1', timestamp, payload)}")
    expect(verifier.verify!(payload: payload, headers: rotated)).to be_a(Hash)
  end

  it "rejects tampered payloads, bad signatures, stale timestamps and missing headers" do
    expect { verifier.verify!(payload: payload.sub("created", "deleted"), headers: headers) }.to raise_error(ClerkAuth::InvalidWebhook)
    expect { verifier.verify!(payload: payload, headers: headers(signature: "bm9wZQ==")) }.to raise_error(ClerkAuth::InvalidWebhook)
    old = 10.minutes.ago.to_i.to_s
    expect { verifier.verify!(payload: payload, headers: headers(signature: verifier.sign("msg_1", old, payload), ts: old)) }
      .to raise_error(ClerkAuth::InvalidWebhook, /tolerance/)
    expect { verifier.verify!(payload: payload, headers: {}) }.to raise_error(ClerkAuth::InvalidWebhook, /missing/)
  end
end
