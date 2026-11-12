require "rails_helper"

RSpec.describe IdentityIntegrators::WithdrawVotesWhenUserDeleted do
  it "withdraws every active vote of a deleted user (and only theirs)" do
    events = create_list(:catalog_event, 2)
    events.each { |event| command_bus.call(Voting::CastVote.new(event_tid: event.tid, user_id: "user_gone1234", value: "up")) }
    command_bus.call(Voting::CastVote.new(event_tid: events.first.tid, user_id: "user_stays123", value: "down"))

    perform_enqueued_jobs do
      command_bus.call(Identity::DeleteUser.new(clerk_user_id: "user_gone1234"))
    end

    expect(Voting::Vote.active.pluck(:user_id)).to eq([ "user_stays123" ])
    expect(facts_of_type(Voting::VoteWithdrawn).map { |fact| fact.data[:event_tid] }).to match_array(events.map(&:tid))
  end

  it "is subscribed to Identity::UserDeleted asynchronously" do
    expect(described_class.subscribed_facts).to eq([ Identity::UserDeleted ])
    expect(described_class.handler_queue).to eq("default")
  end
end
