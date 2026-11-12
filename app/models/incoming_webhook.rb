# Every incoming webhook is stored before processing: audit log, replayability, and the
# ability to answer the provider fast (processing happens in a job).
class IncomingWebhook < ApplicationRecord
  validates :service, :external_id, presence: true

  scope :unhandled, -> { where(handled_at: nil) }

  # Idempotent on the provider's delivery id: redeliveries return the existing record.
  def self.receive!(service:, external_id:, event_type:, data:)
    create_or_find_by!(service: service, external_id: external_id) do |webhook|
      webhook.event_type = event_type
      webhook.data = data
    end
  end

  def handled? = handled_at.present?

  def mark_as_handled!(handled, at: Time.current)
    update!(handled_at: at, handled: handled, last_error: nil)
  end

  def record_failure!(error)
    update_columns(last_error: "#{error.class}: #{error.message}".truncate(2_000), updated_at: Time.current)
  end
end
