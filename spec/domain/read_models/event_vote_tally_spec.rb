require "rails_helper"

RSpec.describe ReadModels::EventVoteTally do
  let(:event_tid) { create(:catalog_event).tid }
  let(:projector) { described_class::Projector }

  def fact(klass, user_id, previous_vote = nil)
    data = { event_tid: event_tid, user_id: user_id, previous_vote: previous_vote }
    klass.strict(data: data).tap { |f| event_store.publish(f) }
  end

  def tally = described_class.find_by!(event_tid: event_tid)

  it "applies each fact at most once (at-least-once delivery is safe)" do
    upvote = fact(Voting::EventUpvoted, "user_aaaaaa1")

    3.times { projector.handle(upvote) }

    expect(tally).to have_attributes(upvotes: 1, downvotes: 0)
  end

  it "is independent of delivery order" do
    up = fact(Voting::EventUpvoted, "user_aaaaaa1")
    switch = fact(Voting::EventDownvoted, "user_aaaaaa1", "up")

    projector.handle(switch) # arrives first
    expect(tally).to have_attributes(upvotes: -1, downvotes: 1)

    projector.handle(up)
    expect(tally).to have_attributes(upvotes: 0, downvotes: 1)
  end

  it "rebuilds all tallies from the event store" do
    facts = [
      fact(Voting::EventUpvoted, "user_aaaaaa1"),
      fact(Voting::EventUpvoted, "user_bbbbbb2"),
      fact(Voting::EventDownvoted, "user_bbbbbb2", "up"),
      fact(Voting::VoteWithdrawn, "user_aaaaaa1", "up")
    ]
    facts.first(2).each { |f| projector.handle(f) } # projection partially applied / drifted

    expect(described_class.rebuild!).to eq(1)

    expect(tally).to have_attributes(upvotes: 0, downvotes: 1)
    expect(ReadModels::ProcessedFact.where(handler: projector.name).count).to eq(4)
    projector.handle(facts.last) # already accounted for by the rebuild
    expect(tally).to have_attributes(upvotes: 0, downvotes: 1)
  end
end
