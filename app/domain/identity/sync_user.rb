module Identity
  class SyncUser
    include Command::Base

    attribute :clerk_user_id, String
    attribute :email, String
    attribute :first_name, String
    attribute :last_name, String
    attribute :image_url, String

    validates :clerk_user_id, presence: true, format: { with: /\Auser_[A-Za-z0-9]+\z/ }
  end
end
