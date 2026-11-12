# Voting bounded context: users like (upvote) or dislike (downvote) catalog events.
#
# Write model : Voting::Vote - the current ballot of a user for an event (one row, row-locked).
# Event log   : every change is recorded as a fact in Rails Event Store, carrying the user id,
#               in the event's stream and linked into the user's stream for traceability.
# Read model  : ReadModels::EventVoteTally - counters projected asynchronously from the facts.
module Voting
  VALUES = %w[up down].freeze

  EventNotFound = Class.new(StandardError)

  module VoteStreams
    def stream_names
      [ "Voting::Event$#{data.fetch(:event_tid)}", "Voting::User$#{data.fetch(:user_id)}" ]
    end
  end

  class EventUpvoted < Fact
    include VoteStreams
    SCHEMA = { event_tid: String, user_id: String, previous_vote: [ String, NilClass ] }.freeze
  end

  class EventDownvoted < Fact
    include VoteStreams
    SCHEMA = { event_tid: String, user_id: String, previous_vote: [ String, NilClass ] }.freeze
  end

  class VoteWithdrawn < Fact
    include VoteStreams
    SCHEMA = { event_tid: String, user_id: String, previous_vote: String }.freeze
  end

  FACTS = [ EventUpvoted, EventDownvoted, VoteWithdrawn ].freeze

  def self.subscriptions
    [].map(&:subscriptions).reduce({}, :merge)
  end
end
