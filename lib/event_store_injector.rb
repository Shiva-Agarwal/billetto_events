# Mixed into domain objects, services and handlers that publish or read facts.
module EventStoreInjector
  def event_store = Rails.configuration.event_store
end
