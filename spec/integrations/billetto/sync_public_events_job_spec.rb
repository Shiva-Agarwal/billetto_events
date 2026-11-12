require "rails_helper"

RSpec.describe Billetto::SyncPublicEventsJob do
  let(:adapter) { Billetto::FakeAdapter.with_sample_events(count: 12) }

  around { |example| with_configuration(:billetto, adapter) { example.run } }

  it "imports every page and publishes a sync summary fact" do
    totals = described_class.perform_now(page_size: 5)

    expect(totals).to eq(pages: 3, imported: 12, updated: 0, unchanged: 0, rejected: 0)
    expect(Catalog::Event.count).to eq(12)
    expect(event_store).to have_published(an_event(Billetto::PublicEventsSynced).with_data(imported: 12))
      .in_stream("Billetto::PublicEventsSync")
  end

  it "is idempotent across runs" do
    described_class.perform_now(page_size: 5)

    expect(described_class.perform_now(page_size: 5)).to include(imported: 0, unchanged: 12)
    expect(Catalog::Event.count).to eq(12)
  end

  it "honours max_pages" do
    expect(described_class.perform_now(page_size: 5, max_pages: 1)).to include(pages: 1, imported: 5)
  end

  it "retries transient Billetto failures" do
    adapter.fail_with!(Billetto::ConnectionError.new("down"))

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
    expect(Catalog::Event.count).to eq(0)
  end

  it "discards the job on authentication errors (retrying cannot fix a wrong keypair)" do
    adapter.fail_with!(Billetto::AuthenticationError.new("bad keypair"))

    expect { described_class.perform_now }.not_to have_enqueued_job(described_class)
  end
end
