# Application read models: denormalized, query-optimized projections of facts, rebuildable
# at any time from the event store (see lib/tasks/read_models.rake).
module ReadModels
  def self.subscriptions
    [
      EventVoteTally::Projector
    ].map(&:subscriptions).reduce({}, :merge)
  end
end
