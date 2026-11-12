# Identity bounded context: local projection of users managed by Clerk.
# Authentication itself is Clerk's job; this module keeps profile data we may want to show or
# audit, synchronised from Clerk webhooks (see ClerkAuth::WebhookJob).
module Identity
  module UserStream
    def stream_names = [ "Identity::User$#{data.fetch(:user_id)}" ]
  end

  class UserRegistered < Fact
    include UserStream
    SCHEMA = { user_id: String }.freeze
  end

  class UserProfileUpdated < Fact
    include UserStream
    SCHEMA = { user_id: String, changed_attributes: Array }.freeze
  end

  class UserDeleted < Fact
    include UserStream
    SCHEMA = { user_id: String }.freeze
  end

  def self.subscriptions
    [].map(&:subscriptions).reduce({}, :merge)
  end
end
