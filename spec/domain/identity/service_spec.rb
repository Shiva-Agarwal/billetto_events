require "rails_helper"

RSpec.describe Identity::Service do
  def sync(**attrs) = command_bus.call(Identity::SyncUser.new(clerk_user_id: "user_2ident01", **attrs))

  it "registers new users once and publishes profile changes" do
    sync(email: "a@example.com")
    sync(email: "a@example.com")
    sync(email: "b@example.com", first_name: "Bea")

    expect(Identity::User.sole).to have_attributes(email: "b@example.com", first_name: "Bea")
    expect(facts_of_type(Identity::UserRegistered).size).to eq(1)
    expect(event_store).to have_published(
      an_event(Identity::UserProfileUpdated).with_data(user_id: "user_2ident01", changed_attributes: %w[email first_name])
    ).in_stream("Identity::User$user_2ident01")
  end

  it "ignores updates for deleted users and leaves a tombstone for early deletes" do
    command_bus.call(Identity::DeleteUser.new(clerk_user_id: "user_2ident01"))
    sync(email: "late@example.com")

    expect(Identity::User.sole).to have_attributes(email: nil, deleted_at: be_present)
    expect(facts_of_type(Identity::UserDeleted).size).to eq(1)
  end

  it "validates Clerk user ids" do
    expect { command_bus.call(Identity::SyncUser.new(clerk_user_id: "admin")) }.to raise_error(Command::Invalid)
  end
end
