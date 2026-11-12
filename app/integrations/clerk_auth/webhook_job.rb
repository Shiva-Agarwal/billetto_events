module ClerkAuth
  # Processes a stored Clerk webhook (see Webhooks::ClerkController). Idempotent: a webhook is
  # handled once, even if Svix redelivers it or the job is retried.
  class WebhookJob < ApplicationJob
    queue_as :critical
    retry_on StandardError, wait: :polynomially_longer, attempts: 10

    def perform(webhook_id)
      webhook = IncomingWebhook.find(webhook_id)
      return if webhook.handled?

      handled = handle(webhook.event_type, webhook.data.deep_symbolize_keys)
      webhook.mark_as_handled!(handled)
    rescue StandardError => e
      webhook&.record_failure!(e) unless e.is_a?(ActiveRecord::RecordNotFound)
      raise
    end

    private

    # Returns true when the webhook type is relevant to us, false when it was ignored.
    def handle(type, payload)
      user = payload.fetch(:data, {})
      case type
      when "user.created", "user.updated"
        command_bus.call(Identity::SyncUser.new(
          clerk_user_id: user[:id],
          email: primary_email(user),
          first_name: user[:first_name],
          last_name: user[:last_name],
          image_url: user[:image_url]
        ))
        true
      when "user.deleted"
        command_bus.call(Identity::DeleteUser.new(clerk_user_id: user[:id]))
        true
      else
        false
      end
    end

    def primary_email(user)
      emails = Array(user[:email_addresses])
      primary = emails.find { |email| email[:id] == user[:primary_email_address_id] } || emails.first
      primary&.dig(:email_address)
    end
  end
end
