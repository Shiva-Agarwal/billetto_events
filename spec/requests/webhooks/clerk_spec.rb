require "rails_helper"

RSpec.describe "Clerk webhooks", type: :request do
  let(:verifier) { ClerkAuth::FakeAdapter.new.webhook_verifier }

  def deliver(payload, id: "msg_#{SecureRandom.hex(4)}", signature: nil)
    body = payload.to_json
    timestamp = Time.current.to_i.to_s
    post "/webhooks/clerk", params: body, headers: {
      "Content-Type" => "application/json",
      "svix-id" => id,
      "svix-timestamp" => timestamp,
      "svix-signature" => "v1,#{signature || verifier.sign(id, timestamp, body)}"
    }
  end

  def user_payload(type, id: "user_2webhook1")
    {
      type: type, object: "event",
      data: {
        id: id, first_name: "Ada", last_name: "Lovelace", image_url: "https://img.clerk.com/ada.png",
        primary_email_address_id: "idn_2", email_addresses: [
          { id: "idn_1", email_address: "old@example.com" }, { id: "idn_2", email_address: "ada@example.com" }
        ]
      }
    }
  end

  it "stores the webhook, enqueues processing and answers 202 immediately" do
    expect { deliver(user_payload("user.created")) }.to have_enqueued_job(ClerkAuth::WebhookJob).on_queue("critical")

    expect(response).to have_http_status(:accepted)
    expect(IncomingWebhook.sole).to have_attributes(service: "clerk", event_type: "user.created", handled_at: nil)
  end

  it "syncs the user when processed" do
    perform_enqueued_jobs { deliver(user_payload("user.created")) }

    expect(Identity::User.sole).to have_attributes(clerk_user_id: "user_2webhook1", email: "ada@example.com", display_name: "Ada Lovelace")
    expect(event_store).to have_published(an_event(Identity::UserRegistered).with_data(user_id: "user_2webhook1"))
    expect(IncomingWebhook.sole).to have_attributes(handled: true, handled_at: be_present)
  end

  it "deduplicates redeliveries by svix-id" do
    perform_enqueued_jobs do
      deliver(user_payload("user.created"), id: "msg_same")
      deliver(user_payload("user.created"), id: "msg_same")
    end

    expect(IncomingWebhook.count).to eq(1)
    expect(facts_of_type(Identity::UserRegistered).size).to eq(1)
  end

  it "rejects unsigned or tampered webhooks" do
    deliver(user_payload("user.created"), signature: Base64.strict_encode64("forged"))

    expect(response).to have_http_status(:bad_request)
    expect(IncomingWebhook.count).to eq(0)
  end

  it "acknowledges but ignores irrelevant event types" do
    perform_enqueued_jobs { deliver({ type: "session.created", data: { id: "sess_1" } }) }

    expect(IncomingWebhook.sole).to have_attributes(handled: false, handled_at: be_present)
  end

  it "on user.deleted scrubs the profile and withdraws the user's votes (cross-module, async)" do
    event = create(:catalog_event)
    perform_enqueued_jobs do
      deliver(user_payload("user.created"))
      command_bus.call(Voting::CastVote.new(event_tid: event.tid, user_id: "user_2webhook1", value: "up"))
      deliver(user_payload("user.deleted"))
    end

    expect(Identity::User.sole).to have_attributes(email: nil, first_name: nil, deleted_at: be_present)
    expect(Voting::Vote.sole.value).to be_nil
    expect(ReadModels::EventVoteTally.find_by!(event_tid: event.tid)).to have_attributes(upvotes: 0)

    deleted = facts_of_type(Identity::UserDeleted).sole
    withdrawn = facts_of_type(Voting::VoteWithdrawn).sole
    expect(withdrawn.metadata[:causation_id]).to eq(deleted.event_id)
    expect(withdrawn.metadata[:correlation_id]).to eq(deleted.metadata[:correlation_id] || deleted.event_id)
  end
end
