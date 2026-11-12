# Building block for event handlers, process managers, integrators and read model projectors.
#
#   class ReadModels::EventVoteTally::Projector
#     include Handler.async(queue: "read_models")
#     subscribes_to Voting::EventUpvoted, Voting::EventDownvoted
#
#     def call(fact) = ...
#   end
#
# * Handler.sync  - runs inside the publisher's transaction (strong consistency, adds latency).
# * Handler.async - enqueued as an ActiveJob (Sidekiq in production) only AFTER the publishing
#                   transaction commits. The job carries just the fact id and re-reads the fact
#                   from the event store (single source of truth, tiny job payloads). Delivery is
#                   at-least-once, so async handlers must be idempotent.
#
# While a handler runs, the handled fact is set as Command::Context.current_fact, so commands it
# sends get correlation/causation ids (see Command::CorrelationBus).
module Handler
  def self.sync = Sync

  def self.async(queue: "default")
    Module.new do
      extend ActiveSupport::Concern
      include Handler::Base

      included do
        class_attribute :handler_queue, instance_writer: false, default: queue.to_s
      end

      define_singleton_method(:inspect) { "Handler.async(queue: #{queue.inspect})" }

      class_methods do
        def subscriber = Handler::AsyncEnqueuer.new(name, handler_queue)
      end
    end
  end

  module Base
    extend ActiveSupport::Concern
    include EventStoreInjector
    include CommandBusInjector

    included do
      class_attribute :subscribed_facts, instance_writer: false, default: []
    end

    class_methods do
      def subscribes_to(*fact_classes)
        self.subscribed_facts = (subscribed_facts + fact_classes.flatten).uniq
      end

      # { subscriber => [FactClass, ...] } - merged by modules and registered by ApplicationSubscriptions
      def subscriptions = { subscriber => subscribed_facts }

      # Runs the handler for a fact (used by subscribers, async jobs and read model rebuilds).
      def handle(fact)
        Command::Context.with_fact(fact) { new.call(fact) }
      end
    end

    def call(_fact)
      raise NotImplementedError, "#{self.class.name}#call"
    end
  end

  module Sync
    extend ActiveSupport::Concern
    include Handler::Base

    class_methods do
      def subscriber = Handler::SyncRunner.new(name)
    end
  end

  # Subscribers hold the handler *name* and constantize lazily, so they survive code reloading.
  SyncRunner = Struct.new(:handler_name) do
    def call(fact) = handler_name.constantize.handle(fact)
  end

  AsyncEnqueuer = Struct.new(:handler_name, :queue) do
    def call(fact)
      ActiveRecord.after_all_transactions_commit do
        Handler::AsyncJob.set(queue: queue).perform_later(handler_name, fact.event_id)
      end
    end
  end
end
