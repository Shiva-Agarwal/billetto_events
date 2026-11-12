require "rails_helper"

RSpec.describe Catalog::ImportEvents do
  def payload(overrides = {})
    {
      "id" => 1, "title" => "Jazz Night", "description" => "<p>Smooth</p>",
      "startdate" => "2030-06-01T18:00:00Z", "enddate" => "2030-06-01T22:00:00Z",
      "url" => "https://billetto.dk/e/1", "location" => { "city" => "Copenhagen", "country_code" => "DK" },
      "minimum_price" => { "amount_in_cents" => 10_000, "currency" => "DKK" }
    }.merge(overrides)
  end

  def import(*payloads)
    events = payloads.map { |p| Billetto::EventRecord.from_api(p) }
    command_bus.call(described_class.new(source: "billetto", events: events))
  end

  it "stores new events and publishes EventImported in each event's stream" do
    result = import(payload, payload("id" => 2, "title" => "Comedy"))

    expect(result.to_h).to include(imported: 2, updated: 0, unchanged: 0, rejected: 0)
    jazz = Catalog::Event.find_by!(external_id: "1")
    expect(jazz).to have_attributes(title: "Jazz Night", description: "Smooth", city: "Copenhagen", min_price_cents: 10_000)
    expect(event_store).to have_published(
      an_event(Catalog::EventImported).with_data(tid: jazz.tid, source: "billetto", external_id: "1", title: "Jazz Night")
    ).in_stream("Catalog::Event$#{jazz.tid}")
  end

  it "is idempotent: re-importing unchanged events writes no facts and keeps ids" do
    import(payload)
    tid = Catalog::Event.sole.tid

    travel 1.hour do
      result = import(payload)
      expect(result.to_h).to include(imported: 0, updated: 0, unchanged: 1)
      expect(Catalog::Event.sole).to have_attributes(tid: tid, last_synced_at: be_within(1.second).of(Time.current))
    end
    expect(facts_of_type(Catalog::EventImported, Catalog::EventDetailsChanged).size).to eq(1)
  end

  it "updates changed events in place and publishes EventDetailsChanged" do
    import(payload)
    tid = Catalog::Event.sole.tid

    result = import(payload("title" => "Jazz Night (moved)"))

    expect(result.to_h).to include(updated: 1)
    expect(Catalog::Event.sole).to have_attributes(tid: tid, title: "Jazz Night (moved)")
    expect(event_store).to have_published(an_event(Catalog::EventDetailsChanged).with_data(tid: tid)).in_stream("Catalog::Event$#{tid}")
  end

  it "rejects invalid records without failing the rest of the batch" do
    invalid = Billetto::EventRecord.from_api(payload("id" => 3, "enddate" => "2030-05-01T00:00:00Z"))

    result = command_bus.call(described_class.new(source: "billetto", events: [ Billetto::EventRecord.from_api(payload), invalid ]))

    expect(result.to_h).to include(imported: 1, rejected: 1)
    expect(result.rejected.first.errors[:ends_at]).to be_present
    expect(Catalog::Event.pluck(:external_id)).to eq([ "1" ])
  end

  it "collapses duplicates within one batch (last one wins)" do
    import(payload("title" => "First"), payload("title" => "Second"))

    expect(Catalog::Event.sole.title).to eq("Second")
  end

  it "rejects oversized batches and unknown sources" do
    too_many = Array.new(described_class::MAX_BATCH_SIZE + 1) { {} }

    expect { command_bus.call(described_class.new(source: "billetto", events: too_many)) }.to raise_error(Command::Invalid)
    expect { command_bus.call(described_class.new(source: "unknown", events: [])) }.to raise_error(Command::Invalid)
  end
end
