module Catalog
  # Imports one batch (e.g. one API page) of events from an external source.
  # `events` are attribute hashes already translated by the source's anti-corruption layer.
  class ImportEvents
    include Command::Base

    MAX_BATCH_SIZE = 500

    attribute :source, String
    attribute :events, Array, default: -> { [] }

    validates :source, inclusion: { in: Event::SOURCES }
    validates :events, length: { maximum: MAX_BATCH_SIZE }
  end
end
