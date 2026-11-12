module Voting
  class CastVote
    include Command::Executable

    attribute :event_tid, String
    attribute :user_id, String
    attribute :value, String

    validates :event_tid, :user_id, presence: true
    validates :value, inclusion: { in: VALUES }

    def call
      raise EventNotFound, "event #{event_tid} not found" unless ObjectRepository.exists?(event_tid)

      Vote.ballot_for!(event_tid: event_tid, user_id: user_id).cast!(value)
    end
  end
end
