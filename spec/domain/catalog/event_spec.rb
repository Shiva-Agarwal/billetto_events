require "rails_helper"

# Model tests: data integrity of ingested events.
RSpec.describe Catalog::Event do
  subject(:event) { build(:catalog_event) }

  it "is valid with complete attributes" do
    expect(event).to be_valid
  end

  describe "validations" do
    it "requires a title" do
      event.title = " "
      expect(event).not_to be_valid
      expect(event.errors[:title]).to include("can't be blank")
    end

    it "limits the title length" do
      event.title = "x" * 256
      expect(event).not_to be_valid
    end

    it "requires a start date" do
      event.starts_at = nil
      expect(event).not_to be_valid
      expect(event.errors[:starts_at]).to include("can't be blank")
    end

    it "rejects an end date before the start date" do
      event.ends_at = event.starts_at - 1.minute
      expect(event).not_to be_valid
      expect(event.errors[:ends_at]).to include("must be after the start date")
    end

    it "allows events without an end date" do
      event.ends_at = nil
      expect(event).to be_valid
    end

    it "requires a known source and an external id" do
      event.source = "eventbrite"
      event.external_id = nil
      expect(event).not_to be_valid
      expect(event.errors.attribute_names).to include(:source, :external_id)
    end

    it "requires the external id to be unique per source" do
      create(:catalog_event, external_id: "42")
      event.external_id = "42"
      expect(event).not_to be_valid
      expect(event.errors[:external_id]).to include("has already been taken")
    end

    it "skips the uniqueness query in the :import context (the DB index enforces it)" do
      create(:catalog_event, external_id: "42")
      event.external_id = "42"
      expect(event.valid?(:import)).to be(true)
    end

    it "only accepts http(s) URLs" do
      event.url = "javascript:alert(1)"
      event.image_url = "not a url"
      expect(event).not_to be_valid
      expect(event.errors.attribute_names).to include(:url, :image_url)
    end

    it "requires a currency for priced events and validates price and codes" do
      event.currency = nil
      expect(event).not_to be_valid

      event.assign_attributes(currency: "dkk", min_price_cents: -1, country_code: "Denmark")
      expect(event).not_to be_valid
      expect(event.errors.attribute_names).to include(:currency, :min_price_cents, :country_code)
    end
  end

  describe "database constraints" do
    it "enforces end >= start even when validations are bypassed" do
      event = create(:catalog_event)
      expect { event.update_columns(ends_at: event.starts_at - 1.hour) }.to raise_error(ActiveRecord::StatementInvalid, /catalog_events_ends_after_start/)
    end

    it "enforces source + external id uniqueness" do
      create(:catalog_event, external_id: "7")
      duplicate = build(:catalog_event, external_id: "7")
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "type id" do
    it "assigns an immutable, prefixed type id" do
      event = create(:catalog_event)
      expect(event.tid).to start_with("event_")
      expect(event.to_param).to eq(event.tid)
      expect { event.update!(tid: TypeId.generate("event")) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end

  describe "content digest" do
    it "changes when the content changes" do
      event.validate
      original = event.content_digest

      event.title = "Something else"
      event.validate
      expect(event.content_digest).not_to eq(original)
    end
  end

  describe ".upcoming" do
    it "lists events from today on, chronologically" do
      later = create(:catalog_event, starts_at: 5.days.from_now)
      sooner = create(:catalog_event, starts_at: 1.day.from_now)
      create(:catalog_event, :past)

      expect(described_class.upcoming.chronological).to eq([ sooner, later ])
    end
  end
end
