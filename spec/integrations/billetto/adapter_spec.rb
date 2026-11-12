require "rails_helper"

RSpec.describe Billetto::Adapter do
  subject(:adapter) do
    described_class.new(api_keypair: "key-id:secret", base_url: "https://billetto.test/api/v3", max_retries: 2, retry_interval: 0)
  end

  let(:endpoint) { "https://billetto.test/api/v3/public/events" }
  let(:page_1) { file_fixture("billetto/public_events_page_1.json").read }
  let(:page_2) { file_fixture("billetto/public_events_page_2.json").read }

  def json_response(body, status: 200) = { status: status, body: body, headers: { "Content-Type" => "application/json" } }

  describe "#list_public_events" do
    it "authenticates with the Api-Keypair header and translates events" do
      stub = stub_request(:get, endpoint).with(query: { limit: "2" }, headers: { "Api-Keypair" => "key-id:secret" })
        .to_return(json_response(page_1))

      page = adapter.list_public_events(limit: 2)

      expect(stub).to have_been_requested
      expect(page.has_more).to be(true)
      expect(page.records.size).to eq(1)
      expect(page.records.first).to include(
        external_id: "1001", title: "Copenhagen Jazz Night", city: "Copenhagen", country_code: "DK",
        min_price_cents: 15_000, currency: "DKK", image_url: "https://cdn.billetto.dk/images/1001.jpg",
        description: "Live jazz & cocktails.\nDoors at 19:00."
      )
    end

    it "reports records that cannot be translated instead of failing the page" do
      stub_request(:get, endpoint).with(query: hash_including({})).to_return(json_response(page_1))

      expect(adapter.list_public_events.rejections).to eq([ { external_id: "1002", reason: "missing or invalid start date" } ])
    end

    it "caps the page size" do
      stub = stub_request(:get, endpoint).with(query: { limit: "100" }).to_return(json_response(page_2))
      adapter.list_public_events(limit: 10_000)
      expect(stub).to have_been_requested
    end
  end

  describe "#each_page" do
    it "follows next_url until has_more is false" do
      stub_request(:get, endpoint).with(query: { limit: "2" }).to_return(json_response(page_1))
      stub_request(:get, endpoint).with(query: { after: "1002", limit: "2" }).to_return(json_response(page_2))

      ids = adapter.each_page(page_size: 2).flat_map { |page| page.records.pluck(:external_id) }

      expect(ids).to eq(%w[1001 1003])
    end

    it "stops after max_pages" do
      stub_request(:get, endpoint).with(query: { limit: "2" }).to_return(json_response(page_1))

      expect(adapter.each_page(page_size: 2, max_pages: 1).count).to eq(1)
    end

    it "never sends the keypair to another host" do
      hostile = JSON.parse(page_1).merge("next_url" => "https://evil.example/steal").to_json
      stub_request(:get, endpoint).with(query: hash_including({})).to_return(json_response(hostile))

      expect { adapter.each_page.to_a }.to raise_error(Billetto::InvalidResponseError, /untrusted host/)
      expect(a_request(:get, /evil\.example/)).not_to have_been_made
    end
  end

  describe "error handling" do
    it "maps 401 to AuthenticationError without retrying" do
      stub = stub_request(:get, endpoint).with(query: hash_including({})).to_return(status: 401, body: "{}")

      expect { adapter.list_public_events }.to raise_error(Billetto::AuthenticationError)
      expect(stub).to have_been_requested.once
    end

    it "retries 5xx responses and then raises ServerError" do
      stub = stub_request(:get, endpoint).with(query: hash_including({})).to_return(status: 503, body: "")

      expect { adapter.list_public_events }.to raise_error(Billetto::ServerError)
      expect(stub).to have_been_requested.times(3)
    end

    it "recovers when a retry succeeds" do
      stub_request(:get, endpoint).with(query: hash_including({}))
        .to_return({ status: 502, body: "" }, json_response(page_2))

      expect(adapter.list_public_events.records.size).to eq(1)
    end

    it "maps 429 to RateLimitedError after retries" do
      stub_request(:get, endpoint).with(query: hash_including({})).to_return(status: 429, body: "")
      expect { adapter.list_public_events }.to raise_error(Billetto::RateLimitedError)
    end

    it "maps timeouts to ConnectionError" do
      stub_request(:get, endpoint).with(query: hash_including({})).to_timeout
      expect { adapter.list_public_events }.to raise_error(Billetto::ConnectionError)
    end

    it "rejects invalid JSON and unexpected payloads" do
      stub_request(:get, endpoint).with(query: hash_including({}))
        .to_return(json_response("<html>"), json_response('{"error":"nope"}'))

      expect { adapter.list_public_events }.to raise_error(Billetto::InvalidResponseError, /invalid JSON/)
      expect { adapter.list_public_events }.to raise_error(Billetto::InvalidResponseError, /data/)
    end
  end

  it "does not leak the keypair when inspected" do
    expect(adapter.inspect).not_to include("secret")
  end

  it "requires a key:secret keypair" do
    expect { described_class.new(api_keypair: "") }.to raise_error(ArgumentError)
  end
end
