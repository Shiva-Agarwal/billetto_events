module Command
  # When a command is executed in the context of a domain event handler (process manager,
  # integrator, async handler) every fact published while executing it gets:
  #   correlation_id - the correlation id of the handled fact (or its id when it starts a chain)
  #   causation_id   - the id of the handled fact
  # This lets us reconstruct "what caused what" across modules and asynchronous boundaries.
  class CorrelationBus
    def initialize(next_bus, event_store:)
      @next_bus = next_bus
      @event_store = event_store
    end

    def call(command)
      fact = Context.current_fact
      return @next_bus.call(command) unless fact

      metadata = {
        correlation_id: fact.metadata[:correlation_id] || fact.event_id,
        causation_id: fact.event_id
      }
      @event_store.with_metadata(metadata) { @next_bus.call(command) }
    end
  end
end
