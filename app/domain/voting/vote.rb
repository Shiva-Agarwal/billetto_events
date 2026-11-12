module Voting
  class Vote < ApplicationRecord
    include EventStoreInjector

    self.table_name = "voting_votes"

    validates :event_tid, :user_id, presence: true
    validates :value, inclusion: { in: VALUES }, allow_nil: true

    scope :active, -> { where.not(value: nil) }

    # Returns the ballot row, creating it on first vote, locked FOR UPDATE for the rest of the
    # surrounding (command bus) transaction. Concurrent requests of the same user for the same
    # event (double clicks, two tabs) are therefore serialized; the unique index makes the
    # "first vote" race safe (create_or_find_by retries as a find on RecordNotUnique).
    def self.ballot_for!(event_tid:, user_id:)
      create_or_find_by!(event_tid: event_tid, user_id: user_id).tap(&:lock!)
    end

    # Idempotent: casting the same vote again is a no-op and publishes nothing.
    def cast!(new_value)
      raise ArgumentError, "invalid vote #{new_value.inspect}" unless VALUES.include?(new_value)
      return false if value == new_value

      previous_vote = value
      update!(value: new_value)
      fact_class = new_value == "up" ? EventUpvoted : EventDownvoted
      event_store.publish(fact_class.strict(data: { event_tid: event_tid, user_id: user_id, previous_vote: previous_vote }))
      true
    end

    def withdraw!
      return false if value.nil?

      previous_vote = value
      update!(value: nil)
      event_store.publish(VoteWithdrawn.strict(data: { event_tid: event_tid, user_id: user_id, previous_vote: previous_vote }))
      true
    end
  end
end
