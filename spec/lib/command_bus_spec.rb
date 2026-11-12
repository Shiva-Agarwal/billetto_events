require "rails_helper"

RSpec.describe "Application command bus" do
  let(:fact_class) do
    stub_const("BusSpecHappened", Class.new(Fact) do
      const_set(:SCHEMA, { name: String }.freeze)
      def stream_names = [ "BusSpec" ]
    end)
  end

  let(:command_class) do
    fact_class
    stub_const("BusSpecCommand", Class.new do
      include Command::Executable

      attribute :name, String
      attribute :explode, :boolean, default: false
      validates :name, presence: true

      def call
        Catalog::Event.create!(FactoryBot.attributes_for(:catalog_event, title: name))
        event_store.publish(BusSpecHappened.strict(data: { name: name }))
        raise "boom" if explode

        :done
      end
    end)
  end

  it "executes self-executing commands and returns their result" do
    expect(command_bus.call(command_class.new(name: "Gig"))).to eq(:done)
    expect(Catalog::Event.where(title: "Gig")).to exist
  end

  it "rejects invalid commands before executing them" do
    expect { command_bus.call(command_class.new(name: " ")) }
      .to raise_error(Command::Invalid, /Name can't be blank/)
    expect(Catalog::Event.count).to eq(0)
  end

  it "wraps execution in a transaction: state and facts roll back together" do
    expect { command_bus.call(command_class.new(name: "Gig", explode: true)) }.to raise_error("boom")

    expect(Catalog::Event.count).to eq(0)
    expect(facts_in("BusSpec")).to be_empty
  end

  it "instruments every command" do
    events = []
    callback = ->(event) { events << event.payload[:command_name] }

    ActiveSupport::Notifications.subscribed(callback, "call.command_bus") do
      command_bus.call(command_class.new(name: "Gig"))
    end

    expect(events).to eq([ "BusSpecCommand" ])
  end

  it "adds correlation & causation ids when executed while handling a fact" do
    cause = fact_class.strict(data: { name: "cause" }, metadata: { correlation_id: "corr-123" })

    Command::Context.with_fact(cause) { command_bus.call(command_class.new(name: "Gig")) }

    effect = facts_in("BusSpec").last
    expect(effect.metadata[:correlation_id]).to eq("corr-123")
    expect(effect.metadata[:causation_id]).to eq(cause.event_id)
  end

  it "raises for plain commands without a registered handler" do
    plain = stub_const("UnhandledCommand", Class.new { include Command::Base })

    expect { command_bus.call(plain.new) }.to raise_error(Command::UnregisteredCommand)
  end

  it "rejects unknown attributes" do
    expect { command_class.new(name: "x", nope: 1) }.to raise_error(ArgumentError, /unknown attributes/)
  end
end
