module Catalog
  class Event < ApplicationRecord
    include HasTypeid

    self.table_name = "catalog_events"
    has_typeid :event

    SOURCES = %w[billetto].freeze

    # Attributes that define the "content" of an event. A change in any of them changes the
    # digest, which is how ingestion detects updates without comparing column by column.
    DIGESTED_ATTRIBUTES = %w[
      title description starts_at ends_at url image_url venue_name city country_code
      organiser_name min_price_cents currency
    ].freeze

    validates :source, inclusion: { in: SOURCES }
    validates :external_id, presence: true, length: { maximum: 64 }
    # Skipped in the :import context - bulk ingestion relies on the unique index instead of
    # issuing one SELECT per record.
    validates :external_id, uniqueness: { scope: :source }, on: %i[create update]
    validates :title, presence: true, length: { maximum: 255 }
    validates :description, length: { maximum: 20_000 }
    validates :starts_at, presence: true
    validate :ends_at_cannot_be_before_starts_at
    validate :urls_must_be_http
    validates :min_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
    validates :currency, presence: true, if: -> { min_price_cents.present? }
    validates :country_code, format: { with: /\A[A-Z]{2}\z/ }, allow_nil: true
    validates :last_synced_at, presence: true

    before_validation :assign_content_digest
    before_save :assign_content_digest

    scope :upcoming, ->(now = Time.current) { where(starts_at: now.beginning_of_day..) }
    scope :chronological, -> { order(:starts_at, :id) }

    def self.digest_for(attributes)
      attributes = attributes.stringify_keys
      normalized = DIGESTED_ATTRIBUTES.map do |name|
        value = attributes[name]
        value.respond_to?(:utc) ? value.utc.iso8601(6) : value
      end
      Digest::SHA256.hexdigest(normalized.to_json)
    end

    def free? = min_price_cents&.zero?

    def ended?(now = Time.current) = (ends_at || starts_at) < now

    private

    def assign_content_digest
      self.content_digest = self.class.digest_for(attributes)
    end

    def ends_at_cannot_be_before_starts_at
      return if ends_at.blank? || starts_at.blank?

      errors.add(:ends_at, "must be after the start date") if ends_at < starts_at
    end

    def urls_must_be_http
      { url: url, image_url: image_url }.each do |attribute, value|
        next if value.blank?

        uri = URI.parse(value)
        errors.add(attribute, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        errors.add(attribute, "must be an http(s) URL")
      end
    end
  end
end
