require "rails_helper"

RSpec.describe TypeId do
  it "generates <prefix>_<26 char base32 suffix>" do
    expect(described_class.generate("event")).to match(/\Aevent_[0-7][0-9a-hjkmnp-tv-z]{25}\z/)
  end

  it "generates time-ordered (k-sortable) ids" do
    ids = Array.new(5) { described_class.generate("event").tap { sleep 0.002 } }

    expect(ids.sort).to eq(ids)
  end

  it "round-trips UUIDs through encode/decode" do
    uuid = described_class.uuid_v7

    expect(described_class.decode(described_class.encode(uuid))).to eq(uuid)
  end

  it "parses valid ids and rejects malformed ones" do
    tid = described_class.generate("event")

    expect(described_class.parse(tid).first).to eq("event")
    expect { described_class.parse("event_123") }.to raise_error(TypeId::InvalidTypeId)
    expect { described_class.parse("nope") }.to raise_error(TypeId::InvalidTypeId)
    expect { described_class.generate("Bad-Prefix") }.to raise_error(TypeId::InvalidTypeId)
  end
end
