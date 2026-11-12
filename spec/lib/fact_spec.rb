require "rails_helper"

RSpec.describe Fact do
  let(:fact_class) do
    stub_const("SpecFact", Class.new(Fact) do
      const_set(:SCHEMA, { id: String, note: [ String, NilClass ], count: Integer }.freeze)
      def stream_names = [ "Spec$#{data.fetch(:id)}", "SpecIndex" ]
    end)
  end

  describe ".strict" do
    it "builds a fact whose data matches the schema" do
      fact = fact_class.strict(data: { id: "a", note: nil, count: 1 })

      expect(fact.data).to eq(id: "a", note: nil, count: 1)
      expect(fact.event_id).to be_present
    end

    it "accepts string keys and symbolizes them" do
      expect(fact_class.strict(data: { "id" => "a", "note" => "x", "count" => 2 }).data).to eq(id: "a", note: "x", count: 2)
    end

    it "rejects missing keys" do
      expect { fact_class.strict(data: { id: "a", count: 1 }) }
        .to raise_error(Fact::SchemaViolation, /missing keys \[:note\]/)
    end

    it "rejects unknown keys" do
      expect { fact_class.strict(data: { id: "a", note: nil, count: 1, extra: true }) }
        .to raise_error(Fact::SchemaViolation, /unknown keys \[:extra\]/)
    end

    it "rejects values of the wrong type" do
      expect { fact_class.strict(data: { id: 1, note: nil, count: 1 }) }
        .to raise_error(Fact::SchemaViolation, /id must be String, got Integer/)
    end
  end

  describe "publishing through ApplicationEventStore" do
    it "publishes to the first stream and links the fact to the other streams" do
      fact = fact_class.strict(data: { id: "a", note: nil, count: 1 })

      event_store.publish(fact)

      expect(event_store).to have_published(an_event(fact_class).with_data(id: "a")).in_stream("Spec$a")
      expect(facts_in("SpecIndex").map(&:event_id)).to eq([ fact.event_id ])
    end
  end
end
