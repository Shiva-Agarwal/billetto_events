module Billetto
  # Translates one Billetto API event into Catalog::Event attributes.
  # First line of defence for data validation: structurally broken records are rejected here
  # (with a reason); business rules are enforced again by the Catalog::Event model.
  module EventRecord
    Invalid = Class.new(Billetto::Error)

    module_function

    def from_api(payload)
      raise Invalid, "event payload is not an object" unless payload.is_a?(Hash)

      external_id = payload["id"].to_s.strip
      raise Invalid, "missing id" if external_id.empty?

      title = text(payload["title"] || payload["name"])
      raise Invalid, "missing title" if title.blank?

      starts_at = time(payload["startdate"] || payload["start_date"] || payload["starts_at"])
      raise Invalid, "missing or invalid start date" unless starts_at

      location = payload["location"].is_a?(Hash) ? payload["location"] : {}
      organiser = payload["organiser"] || payload["organizer"]
      price = payload["minimum_price"].is_a?(Hash) ? payload["minimum_price"] : {}

      {
        external_id: external_id,
        title: title.truncate(255),
        description: html_to_text(payload["description"]),
        starts_at: starts_at,
        ends_at: time(payload["enddate"] || payload["end_date"] || payload["ends_at"]),
        url: payload["url"].presence,
        image_url: (payload["image_link"] || payload["image_url"] || payload.dig("image", "url")).presence,
        venue_name: text(location["location_name"] || location["name"]),
        city: text(location["city"]),
        country_code: (location["country_code"] || payload["country_code"]).presence&.to_s&.upcase,
        organiser_name: text(organiser.is_a?(Hash) ? organiser["name"] : organiser),
        min_price_cents: integer(price["amount_in_cents"] || price["amount"]),
        currency: price["currency"].presence&.to_s&.upcase,
        raw_payload: payload
      }
    end

    def time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def integer(value)
      Integer(value, exception: false) if value.present?
    end

    def text(value)
      value.to_s.squish.presence
    end

    def html_to_text(value)
      return if value.blank?

      html = value.to_s.gsub(%r{<(script|style)\b[^>]*>.*?</\1\s*>}im, "").gsub(/<br\s*\/?>|<\/p>/i, "\n")
      ActionView::Base.full_sanitizer.sanitize(html)
        .then { |text| CGI.unescapeHTML(text) }
        .gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip.presence
    end
  end
end
