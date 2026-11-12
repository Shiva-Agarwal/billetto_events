require "rails_helper"

RSpec.describe Handler do
  let(:fact_class) do
    stub_const("HandlerSpecFact", Class.new(Fact) do
      const_set(:SCHEMA, { n: Integer }.freeze)
      def stream_names = [ "HandlerSpec" ]
    end)
  end

  let(:async_handler) do
    stub_const("HandlerSpecAsync", Class.new do
      include Handler.async(queue: "low")
      cattr_accessor :handled, default: []

      def call(fact) = handled << [ fact.event_id, Command::Context.current_fact&.event_id ]
    end)
  end

  let(:sync_handler) do
    stub_const("HandlerSpecSync", Class.new do
      include Handler.sync
      cattr_accessor :handled, default: []

      def call(fact) = handled << fact.data[:n]
    end)
  end

  before do
    async_handler.subscribes_to(fact_class)
    sync_handler.subscribes_to(fact_class)
  end

  it "exposes subscriptions as { subscriber => facts }" do
    expect(async_handler.subscriptions.values).to eq([ [ fact_class ] ])
    expect(async_handler.subscriptions.keys.first).to have_attributes(handler_name: "HandlerSpecAsync", queue: "low")
  end

  it "runs sync handlers inline and async handlers as a job after commit, re-reading the fact" do
    with_subscription(sync_handler.subscriber, to: fact_class) do
      with_subscription(async_handler.subscriber, to: fact_class) do
        fact = fact_class.strict(data: { n: 1 })

        ActiveRecord::Base.transaction do
          event_store.publish(fact)
          expect(sync_handler.handled).to eq([ 1 ])
          expect(enqueued_jobs).to be_empty # not before commit
        end

        expect(Handler::AsyncJob).to have_been_enqueued.with("HandlerSpecAsync", fact.event_id).on_queue("low")
        perform_enqueued_jobs
        expect(async_handler.handled).to eq([ [ fact.event_id, fact.event_id ] ])
      end
    end
  end

  it "does not enqueue async handlers when the publishing transaction rolls back" do
    with_subscription(async_handler.subscriber, to: fact_class) do
      ActiveRecord::Base.transaction do
        event_store.publish(fact_class.strict(data: { n: 2 }))
        raise ActiveRecord::Rollback
      end

      expect(enqueued_jobs).to be_empty
    end
  end
end
