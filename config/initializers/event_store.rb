# Rails Event Store setup.
#
# * JSONClient stores facts in jsonb columns (queryable, indexable) and preserves Ruby types
#   (symbols, Time, BigDecimal) through RES' PreserveTypes transformation.
# * The client is wrapped by ApplicationEventStore so `publish(fact)` honours `fact.stream_names`.
# * The command bus and all handler subscriptions are (re)built in `to_prepare`, so they are
#   reload-safe in development.
Rails.configuration.to_prepare do
  event_store = ApplicationEventStore.new(RailsEventStore::JSONClient.new)

  Rails.configuration.event_store = event_store
  Rails.configuration.command_bus = ApplicationCommandBus.build(event_store: event_store)

  ApplicationSubscriptions.new(event_store).call
end
