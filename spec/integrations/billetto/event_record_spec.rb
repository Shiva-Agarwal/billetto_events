require "rails_helper"

RSpec.describe Billetto::EventRecord do
  let(:payload) { JSON.parse(file_fixture("billetto/public_events_page_1.json").read)["data"].first }

  it "translates a Billetto event into catalog attributes" do
    expect(described_class.from_api(payload)).to include(
      external_id: "1001",
      title: "Copenhagen Jazz Night",
      starts_at: Time.utc(2030, 6, 1, 18),
      ends_at: Time.utc(2030, 6, 1, 22),
      url: "https://billetto.dk/e/copenhagen-jazz-night-1001",
      venue_name: "Jazzhouse",
      organiser_name: "Jazzhouse ApS",
      raw_payload: payload
    )
  end

  it "turns HTML descriptions into plain text" do
    expect(described_class.from_api(payload.merge("description" => "<script>x()</script><b>Hi</b><br>there")).fetch(:description))
      .to eq("Hi\nthere")
  end

  it "rejects structurally broken records" do
    expect { described_class.from_api(payload.except("id")) }.to raise_error(described_class::Invalid, "missing id")
    expect { described_class.from_api(payload.merge("title" => "  ")) }.to raise_error(described_class::Invalid, "missing title")
    expect { described_class.from_api(payload.merge("startdate" => "soon")) }.to raise_error(described_class::Invalid, /start date/)
    expect { described_class.from_api("nope") }.to raise_error(described_class::Invalid)
  end
end
