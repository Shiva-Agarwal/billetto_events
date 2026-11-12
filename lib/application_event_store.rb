# Thin decorator around the Rails Event Store client.
#
# `publish(fact)` publishes to the fact's main stream (first of `fact.stream_names`) and links
# it into every other stream it declares, so read models / audits can read e.g. all votes of a
# user ("Voting::User$<id>") without scanning the global stream.
# Everything else (read, subscribe, link, with_metadata, ...) is delegated to RES untouched.
class ApplicationEventStore < SimpleDelegator
  def publish(facts, stream_name: nil, expected_version: :any)
    return __getobj__.publish(facts, stream_name: stream_name, expected_version: expected_version) if stream_name

    Array(facts).each do |fact|
      main_stream, *linked_streams = fact.stream_names
      __getobj__.publish(fact, stream_name: main_stream || RubyEventStore::GLOBAL_STREAM, expected_version: expected_version)
      linked_streams.each { |stream| __getobj__.link(fact.event_id, stream_name: stream) }
    end
    self
  end

  def client = __getobj__
end
