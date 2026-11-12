module Identity
  class DeleteUser
    include Command::Base

    attribute :clerk_user_id, String
    validates :clerk_user_id, presence: true
  end
end
