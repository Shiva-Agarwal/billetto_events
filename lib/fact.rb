# Base class for all domain events ("facts") published to Rails Event Store.
#
# Every fact declares:
#   * SCHEMA       - the exact payload contract (key => Class or [Classes]); enforced by `.strict`
#   * stream_names - streams the fact belongs to. The first one is the main stream the fact is
#                    published to, the rest are linked (see ApplicationEventStore#publish).
#
#   class EventUpvoted < Fact
#     SCHEMA = { event_tid: String, user_id: String, previous_vote: [String, NilClass] }.freeze
#     def stream_names = ["Voting::Event$#{data.fetch(:event_tid)}"]
#   end
class Fact < RubyEventStore::Event
  SchemaViolation = Class.new(ArgumentError)
  SCHEMA = {}.freeze

  class << self
    # Builds a fact after validating `data` against SCHEMA. Use it whenever publishing:
    # a fact is an immutable, persisted contract and must never be published malformed.
    def strict(data:, metadata: {})
      data = data.to_h.symbolize_keys
      validate!(data)
      new(data: data, metadata: metadata)
    end

    def validate!(data)
      schema = self::SCHEMA
      missing = schema.keys - data.keys
      unknown = data.keys - schema.keys
      raise SchemaViolation, "#{name}: missing keys #{missing.inspect}" if missing.any?
      raise SchemaViolation, "#{name}: unknown keys #{unknown.inspect}" if unknown.any?

      schema.each do |key, types|
        value = data.fetch(key)
        next if Array(types).any? { |type| type === value }

        raise SchemaViolation, "#{name}: #{key} must be #{Array(types).join(' | ')}, got #{value.class}"
      end
      true
    end
  end

  def stream_names = []
end
