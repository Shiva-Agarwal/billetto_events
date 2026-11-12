module Voting
  # Used when a user account is deleted (see IdentityIntegrators): withdraws every active vote,
  # publishing VoteWithdrawn facts so the tallies are corrected through the normal projection.
  class WithdrawAllVotes
    include Command::Executable

    attribute :user_id, String
    validates :user_id, presence: true

    def call
      Vote.active.where(user_id: user_id).lock.order(:id).to_a.count(&:withdraw!)
    end
  end
end
