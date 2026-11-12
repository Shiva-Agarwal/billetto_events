require "rails_helper"

# Event Store tests: votes are recorded as facts (with the user id) and drive the counts.
RSpec.describe "Voting" do
  let(:event) { create(:catalog_event) }
  let(:alice) { "user_alice123" }
  let(:bob) { "user_bob45678" }

  def cast(user_id, value) = command_bus.call(Voting::CastVote.new(event_tid: event.tid, user_id: user_id, value: value))
  def withdraw(user_id) = command_bus.call(Voting::WithdrawVote.new(event_tid: event.tid, user_id: user_id))

  describe Voting::CastVote do
    it "publishes EventUpvoted with the user id to the event stream, linked to the user stream" do
      cast(alice, "up")

      expected = an_event(Voting::EventUpvoted).with_data(event_tid: event.tid, user_id: alice, previous_vote: nil)
      expect(event_store).to have_published(expected).in_stream("Voting::Event$#{event.tid}")
      expect(event_store).to have_published(expected).in_stream("Voting::User$#{alice}")
      expect(Voting::Vote.find_by!(event_tid: event.tid, user_id: alice).value).to eq("up")
    end

    it "publishes EventDownvoted remembering the previous vote when switching" do
      cast(alice, "up")
      cast(alice, "down")

      expect(event_store).to have_published(
        an_event(Voting::EventDownvoted).with_data(event_tid: event.tid, user_id: alice, previous_vote: "up")
      )
      expect(Voting::Vote.where(event_tid: event.tid).pluck(:value)).to eq([ "down" ])
    end

    it "is idempotent: repeating the same vote publishes nothing" do
      cast(alice, "up")
      expect { cast(alice, "up") }.not_to change { facts_in("Voting::Event$#{event.tid}").size }
    end

    it "keeps one ballot per user and event" do
      cast(alice, "up")
      cast(alice, "down")
      cast(bob, "up")

      expect(Voting::Vote.count).to eq(2)
    end

    it "rejects invalid votes" do
      expect { cast(alice, "maybe") }.to raise_error(Command::Invalid, /Value is not included/)
      expect { cast(nil, "up") }.to raise_error(Command::Invalid, /User can't be blank/)
      expect(facts_of_type(Voting::FACTS)).to be_empty
    end

    it "rejects votes for unknown events" do
      expect {
        command_bus.call(Voting::CastVote.new(event_tid: TypeId.generate("event"), user_id: alice, value: "up"))
      }.to raise_error(Voting::EventNotFound)
    end
  end

  describe Voting::WithdrawVote do
    it "publishes VoteWithdrawn with the previous vote" do
      cast(alice, "down")
      withdraw(alice)

      expect(event_store).to have_published(
        an_event(Voting::VoteWithdrawn).with_data(event_tid: event.tid, user_id: alice, previous_vote: "down")
      ).in_stream("Voting::User$#{alice}")
      expect(Voting::Vote.sole.value).to be_nil
    end

    it "does nothing when there is no vote to withdraw" do
      withdraw(alice)
      cast(alice, "up")
      withdraw(alice)
      withdraw(alice)

      expect(facts_of_type(Voting::VoteWithdrawn).size).to eq(1)
    end
  end

  describe "counting (ReadModels::EventVoteTally)" do
    def tally = ReadModels::EventVoteTally.find_by(event_tid: event.tid)

    it "counts votes correctly across casts, switches and withdrawals" do
      perform_enqueued_jobs do
        cast(alice, "up")
        cast(bob, "up")
        cast("user_carol9999", "down")
        cast(bob, "down")   # switch: up -1, down +1
        withdraw(alice)     # up -1
      end

      expect(tally).to have_attributes(upvotes: 0, downvotes: 2)
      expect(facts_of_type(Voting::FACTS).size).to eq(5)
    end

    it "projects asynchronously on the read_models queue" do
      cast(alice, "up")

      expect(Handler::AsyncJob).to have_been_enqueued.with(ReadModels::EventVoteTally::Projector.name, anything).on_queue("read_models")
      expect(tally).to be_nil
    end
  end
end
