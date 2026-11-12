require "rails_helper"

RSpec.describe "Events listing", type: :request do
  it "lists upcoming events with title, date, description and vote counts" do
    event = create(:catalog_event, title: "Jazz Night", description: "Smooth tunes", starts_at: Time.utc(2030, 6, 1, 18))
    create(:catalog_event, :past, title: "Old news")
    ReadModels::EventVoteTally.create!(event_tid: event.tid, upvotes: 3, downvotes: 1)

    get root_path

    expect(response).to have_http_status(:ok)
    card = Nokogiri::HTML(response.body).at_css("[data-testid='event-#{event.external_id}']")
    expect(card.text).to include("Jazz Night", "Smooth tunes", "Sat 1 Jun 2030 · 18:00 UTC", "Copenhagen")
    expect(card.at_css("[data-testid='upvotes-count']").text).to eq("3")
    expect(card.at_css("[data-testid='downvotes-count']").text).to eq("1")
    expect(card.at_css("[data-testid='score']").text).to eq("+2")
    expect(response.body).not_to include("Old news")
  end

  it "asks signed-out visitors to sign in to vote" do
    create(:catalog_event)

    get root_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("[data-testid='vote-up']")["title"]).to eq("Sign in to vote")
    expect(html.css("form[data-requires-auth]")).to be_empty
  end

  it "highlights the signed-in user's own vote" do
    event = create(:catalog_event)
    Voting::Vote.create!(event_tid: event.tid, user_id: "user_me123456", value: "down")
    cookies[ClerkAuth::SESSION_COOKIE] = ClerkAuth::FakeAdapter.token_for("user_me123456")

    get root_path

    card = Nokogiri::HTML(response.body).at_css("[data-testid='event-#{event.external_id}']")
    expect(card.at_css("[data-testid='vote-down']")["aria-pressed"]).to eq("true")
    expect(card.at_css("[data-testid='vote-up']")["aria-pressed"]).to eq("false")
  end

  it "paginates with a keyset cursor" do
    events = Array.new(EventListing::PER_PAGE + 2) { |i| create(:catalog_event, starts_at: (i + 1).days.from_now) }

    get root_path
    next_link = Nokogiri::HTML(response.body).at_css("[data-testid='next-page']")["href"]
    get next_link

    titles = Nokogiri::HTML(response.body).css("[data-testid='event-title']").map(&:text)
    expect(titles).to eq(events.last(2).map(&:title))
  end

  it "shows an empty state" do
    get root_path
    expect(response.body).to include("No upcoming events yet.")
  end
end
