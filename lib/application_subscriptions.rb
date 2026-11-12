# Single place where every module's event handlers get subscribed to the event store.
# Each bounded context / integrator module exposes `.subscriptions` ({ subscriber => [facts] }).
class ApplicationSubscriptions
  def initialize(event_store)
    @event_store = event_store
  end

  def call
    handlers.each { |subscriber, facts| @event_store.subscribe(subscriber, to: facts) if facts.any? }
  end

  def handlers
    top_level_subscriptions
      .merge(Catalog.subscriptions)
      .merge(Voting.subscriptions)
      .merge(Identity.subscriptions)
      .merge(ReadModels.subscriptions)
      .merge(IdentityIntegrators.subscriptions)
  end

  private

  def top_level_subscriptions = {}
end
