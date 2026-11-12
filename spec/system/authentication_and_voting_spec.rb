require "rails_helper"

# Browser test (headless Chrome): sign-up, login, logout and voting, end to end through the
# real app stack. Clerk's browser SDK is replaced by vendor/fake_clerk/clerk.js (same JS API
# surface the app uses), so the suite is deterministic and runs offline. The same journey
# against the real Clerk is covered by the Playwright suite in e2e/ (needs Clerk test keys).
RSpec.describe "Authentication and voting", type: :system do
  around { |example| perform_enqueued_jobs { example.run } } # run async projections inline

  let!(:event) { create(:catalog_event, title: "Copenhagen Jazz Night") }
  let(:email) { "ada@example.com" }
  let(:password) { "correct-horse-battery" }

  def card = find("[data-testid='event-#{event.external_id}']")
  def wait_for_clerk = expect(page).to(have_css("html[data-clerk-loaded='true']", visible: :all))
  def vote_count(direction) = card.find("[data-testid='#{direction}votes-count']")

  def vote(direction)
    wait_for_clerk
    card.find("[data-testid='vote-#{direction}']").click
    expect(page).to have_css("[data-testid='flash']")
  end

  def sign_up
    visit sign_up_path
    fill_in "Email address", with: email
    fill_in "Password", with: password
    click_on "Continue"
    expect(page).to have_css("[data-testid='current-user']")
  end

  def sign_in(with_password: password)
    visit sign_in_path
    fill_in "Email address", with: email
    fill_in "Password", with: with_password
    click_on "Continue"
  end

  def sign_out
    wait_for_clerk
    click_on "Sign out"
    expect(page).to have_css("[data-testid='sign-in-link']")
  end

  it "requires signing in before voting" do
    visit root_path

    expect(page).to have_content("Copenhagen Jazz Night")
    card.find("[data-testid='vote-up']").click

    expect(page).to have_current_path(/\A\/sign_in/)
    expect(page).to have_css("[data-testid='clerk-sign-in']")
    expect(Voting::Vote.count).to eq(0)
  end

  it "signs up, votes, switches, withdraws, signs out and signs back in" do
    visit root_path
    expect(page).to have_css("[data-testid='sign-in-link']")

    sign_up
    user_id = find("[data-testid='current-user']").text
    expect(user_id).to start_with("user_")

    vote("up")
    expect(page).to have_content("Thanks, your vote was recorded.")
    expect(vote_count("up")).to have_text("1")
    expect(card.find("[data-testid='vote-up']")["aria-pressed"]).to eq("true")

    vote("down")
    expect(vote_count("up")).to have_text("0")
    expect(vote_count("down")).to have_text("1")

    vote("down") # clicking the active vote withdraws it
    expect(page).to have_content("Your vote was withdrawn.")
    expect(vote_count("down")).to have_text("0")

    vote("up")
    expect(vote_count("up")).to have_text("1")

    sign_out
    expect(card).to have_link(title: "Sign in to vote", count: 2)
    expect(vote_count("up")).to have_text("1") # counts stay public

    sign_in(with_password: "wrong-password")
    expect(page).to have_css("[data-testid='clerk-error']", text: "Password is incorrect")

    sign_in
    expect(page).to have_css("[data-testid='current-user']", text: user_id)
    expect(card.find("[data-testid='vote-up']")["aria-pressed"]).to eq("true") # vote remembered

    expect(facts_of_type(Voting::FACTS).map { |fact| [ fact.event_type, fact.data[:user_id] ] }).to eq([
      [ "Voting::EventUpvoted", user_id ],
      [ "Voting::EventDownvoted", user_id ],
      [ "Voting::VoteWithdrawn", user_id ],
      [ "Voting::EventUpvoted", user_id ]
    ])
  end

  it "does not let an unknown account sign in" do
    sign_in
    expect(page).to have_css("[data-testid='clerk-error']", text: "Couldn't find your account")
    expect(page).to have_no_css("[data-testid='current-user']")
  end
end
