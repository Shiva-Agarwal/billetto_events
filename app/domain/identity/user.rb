module Identity
  class User < ApplicationRecord
    self.table_name = "identity_users"

    PROFILE_ATTRIBUTES = %w[email first_name last_name image_url].freeze

    validates :clerk_user_id, presence: true, uniqueness: true

    scope :active, -> { where(deleted_at: nil) }

    def display_name
      [ first_name, last_name ].compact_blank.join(" ").presence || email.presence || clerk_user_id
    end

    def deleted? = deleted_at.present?
  end
end
