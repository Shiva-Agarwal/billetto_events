module EventStoreHelpers
  def event_store = Rails.configuration.event_store
  def command_bus = Rails.configuration.command_bus

  def facts_in(stream) = event_store.read.stream(stream).to_a

  def facts_of_type(*types) = event_store.read.of_type(types.flatten).to_a

  # Temporarily replaces a Rails.configuration entry (e.g. an adapter) for one example.
  def with_configuration(key, value)
    previous = Rails.configuration.public_send(key)
    Rails.configuration.public_send(:"#{key}=", value)
    yield
  ensure
    Rails.configuration.public_send(:"#{key}=", previous)
  end

  # Subscribes a handler for the duration of the block (keeps the global event store clean).
  def with_subscription(subscriber, to:)
    unsubscribe = event_store.subscribe(subscriber, to: Array(to))
    yield
  ensure
    unsubscribe&.call
  end
end
