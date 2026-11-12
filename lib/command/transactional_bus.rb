module Command
  # Wraps the execution (state change + facts published to RES + sync handlers) in a single
  # database transaction, so the write model and the event log can never diverge.
  # Nested commands (a command sent from within a sync handler) join the outer transaction.
  class TransactionalBus
    def initialize(next_bus, transaction: ActiveRecord::Base.method(:transaction))
      @next_bus = next_bus
      @transaction = transaction
    end

    def call(command)
      @transaction.call { @next_bus.call(command) }
    end
  end
end
