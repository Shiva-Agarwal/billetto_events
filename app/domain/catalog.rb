# Catalog bounded context: the events (concerts, shows, ...) users can browse and vote on.
# Events are ingested from external sources (Billetto) through the ImportEvents command.
module Catalog
  class EventImported < Fact
    SCHEMA = {
      tid: String,
      source: String,
      external_id: String,
      title: String,
      starts_at: String
    }.freeze

    def stream_names = [ "Catalog::Event$#{data.fetch(:tid)}" ]
  end

  class EventDetailsChanged < Fact
    SCHEMA = {
      tid: String,
      source: String,
      external_id: String,
      content_digest: String
    }.freeze

    def stream_names = [ "Catalog::Event$#{data.fetch(:tid)}" ]
  end

  def self.subscriptions
    [].map(&:subscriptions).reduce({}, :merge)
  end
end
