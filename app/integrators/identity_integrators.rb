# Cross-module collaboration lives in integrators, never inside a domain module:
# Identity knows nothing about Voting and vice versa.
module IdentityIntegrators
  # When a user is deleted in Clerk, withdraw all of their votes. Runs async; the
  # WithdrawAllVotes command gets correlation/causation ids pointing at the UserDeleted fact.
  class WithdrawVotesWhenUserDeleted
    include Handler.async(queue: "default")
    subscribes_to Identity::UserDeleted

    def call(fact)
      command_bus.call(Voting::WithdrawAllVotes.new(user_id: fact.data.fetch(:user_id)))
    end
  end

  def self.subscriptions
    [
      WithdrawVotesWhenUserDeleted
    ].map(&:subscriptions).reduce({}, :merge)
  end
end
