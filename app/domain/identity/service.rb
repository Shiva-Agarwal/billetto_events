module Identity
  # Command handler (service object) flavour of commands - see Command::Handler.
  class Service
    include Command::Handler

    handles SyncUser, :sync_user
    handles DeleteUser, :delete_user

    private

    def sync_user(cmd)
      attributes = cmd.to_h.slice(*User::PROFILE_ATTRIBUTES.map(&:to_sym))
      user = find_locked(cmd.clerk_user_id)

      if user.nil?
        user, created = create_user!(clerk_user_id: cmd.clerk_user_id, **attributes)
        if created
          event_store.publish(UserRegistered.strict(data: { user_id: cmd.clerk_user_id }))
          return true
        end
      end
      return false if user.deleted? # Clerk user ids are never reused; ignore late/out-of-order updates

      user.assign_attributes(attributes)
      changed = user.changed
      return false if changed.empty?

      user.save!
      event_store.publish(UserProfileUpdated.strict(data: { user_id: user.clerk_user_id, changed_attributes: changed }))
      true
    end

    # Scrubs personal data (GDPR) and announces the deletion so other modules can react.
    # A deletion arriving before the creation webhook leaves a tombstone, so a late
    # `user.created` cannot resurrect the account.
    def delete_user(cmd)
      user = find_locked(cmd.clerk_user_id) || create_user!(clerk_user_id: cmd.clerk_user_id).first
      return false if user.deleted?

      user.update!(User::PROFILE_ATTRIBUTES.index_with(nil).merge("deleted_at" => Time.current))
      event_store.publish(UserDeleted.strict(data: { user_id: user.clerk_user_id }))
      true
    end

    def find_locked(clerk_user_id) = User.lock.find_by(clerk_user_id: clerk_user_id)

    # Concurrent webhooks for a brand new user: the unique index decides the winner, the loser
    # re-reads (and locks) the row created by the winner. Returns [user, created?].
    def create_user!(**attributes)
      [ User.transaction(requires_new: true) { User.create!(**attributes) }, true ]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if e.is_a?(ActiveRecord::RecordInvalid) && e.record.errors.attribute_names != [ :clerk_user_id ]

      [ find_locked(attributes.fetch(:clerk_user_id)), false ]
    end
  end
end
