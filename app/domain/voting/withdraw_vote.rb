module Voting
  class WithdrawVote
    include Command::Executable

    attribute :event_tid, String
    attribute :user_id, String

    validates :event_tid, :user_id, presence: true

    def call
      vote = Vote.find_by(event_tid: event_tid, user_id: user_id)
      return false unless vote

      vote.lock!.withdraw!
    end
  end
end
