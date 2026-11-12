module Webhooks
  # Receives Clerk (Svix) webhooks: verify signature, store, enqueue, answer 202 immediately.
  class ClerkController < ActionController::API
    def create
      payload = request.raw_post
      data = Rails.configuration.clerk.verify_webhook!(payload: payload, headers: request.headers)

      webhook = IncomingWebhook.receive!(
        service: "clerk",
        external_id: request.headers["svix-id"],
        event_type: data["type"],
        data: data
      )
      ClerkAuth::WebhookJob.perform_later(webhook.id) unless webhook.handled?
      head :accepted
    rescue ClerkAuth::InvalidWebhook => e
      Rails.logger.warn("[webhooks.clerk] rejected: #{e.message}")
      head :bad_request
    end
  end
end
