require "rails_helper"

# Authentication tests: voting is restricted to users with a valid Clerk session.
RSpec.describe "Votes", type: :request do
  let(:event) { create(:catalog_event) }
  let(:user_id) { "user_2voterABC" }
  let(:vote_path) { event_vote_path(event) }

  describe "when not signed in" do
    it "redirects browsers to the sign-in page and records nothing" do
      post vote_path, params: { value: "up" }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(sign_in_path)
      expect(Voting::Vote.count).to eq(0)
      expect(facts_of_type(Voting::FACTS)).to be_empty
    end

    it "answers 401 to API clients" do
      post vote_path, params: { value: "up" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "unauthenticated")
    end

    it "rejects forged or malformed session tokens" do
      post vote_path, params: { value: "up" }.to_json,
        headers: { "Authorization" => "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VyX2V2aWwifQ.", "Content-Type" => "application/json", "Accept" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(Voting::Vote.count).to eq(0)
    end

    it "cannot withdraw votes either" do
      delete vote_path, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "when signed in" do
    it "records the vote for the signed-in user (session cookie, like clerk-js)" do
      sign_in_with_cookie(user_id)

      post vote_path, params: { value: "up" }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Thanks, your vote was recorded.")
      expect(event_store).to have_published(
        an_event(Voting::EventUpvoted).with_data(event_tid: event.tid, user_id: user_id, previous_vote: nil)
      )
    end

    it "records the vote for API clients authenticated with a bearer token" do
      post vote_path, params: { value: "down" }.to_json, headers: auth_headers(user_id).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("event_tid" => event.tid, "my_vote" => "down")
    end

    it "attaches request metadata to the published fact" do
      post vote_path, params: { value: "up" }.to_json, headers: auth_headers(user_id).merge("Content-Type" => "application/json")

      expect(facts_of_type(Voting::EventUpvoted).sole.metadata.to_h).to include(:request_id, :remote_ip, :correlation_id)
    end

    it "withdraws the vote" do
      sign_in_with_cookie(user_id)
      post vote_path, params: { value: "up" }

      delete vote_path

      expect(flash[:notice]).to eq("Your vote was withdrawn.")
      expect(event_store).to have_published(an_event(Voting::VoteWithdrawn).with_data(user_id: user_id, previous_vote: "up"))
    end

    it "rejects invalid votes" do
      post vote_path, params: { value: "love" }.to_json, headers: auth_headers(user_id).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("details", "value")).to be_present
    end

    it "answers 404 for unknown events" do
      post event_vote_path(TypeId.generate("event")), params: { value: "up" }.to_json,
        headers: auth_headers(user_id).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:not_found)
    end
  end
end
