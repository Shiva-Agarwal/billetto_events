module Billetto
  # Deterministic, API-shaped sample payloads used by FakeAdapter (and seeds).
  module SampleEvents
    CITIES = [ [ "Copenhagen", "DK", "DKK" ], [ "Aarhus", "DK", "DKK" ], [ "Stockholm", "SE", "SEK" ], [ "London", "GB", "GBP" ] ].freeze
    KINDS = [ "Jazz Night", "Stand-up Comedy", "Tech Meetup", "Indie Concert", "Food Festival", "Wine Tasting" ].freeze

    module_function

    def build(count:, now:)
      Array.new(count) do |i|
        city, country, currency = CITIES[i % CITIES.size]
        kind = KINDS[i % KINDS.size]
        starts = (now + (i + 1).days).change(hour: 19 + (i % 3), min: 0)
        {
          "id" => (100_000 + i).to_s,
          "title" => "#{kind} in #{city} ##{i + 1}",
          "description" => "<p>An evening of <strong>#{kind.downcase}</strong> in #{city}.</p><p>Doors open one hour before start.</p>",
          "startdate" => starts.utc.iso8601,
          "enddate" => (starts + 3.hours).utc.iso8601,
          "url" => "https://billetto.dk/e/sample-event-#{100_000 + i}",
          "image_link" => nil,
          "location" => { "location_name" => "#{city} Hall", "city" => city, "country_code" => country },
          "organiser" => { "id" => 900 + i, "name" => "#{city} Events ApS" },
          "minimum_price" => { "amount_in_cents" => i.zero? ? 0 : 5_000 + (i * 2_500), "currency" => currency }
        }
      end
    end
  end
end
