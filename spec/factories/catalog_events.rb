FactoryBot.define do
  factory :catalog_event, class: "Catalog::Event" do
    source { "billetto" }
    sequence(:external_id) { |n| (500_000 + n).to_s }
    sequence(:title) { |n| "Sample event #{n}" }
    description { "A great night out in town." }
    starts_at { 3.days.from_now.change(usec: 0) }
    ends_at { starts_at + 3.hours }
    url { "https://billetto.dk/e/sample-#{external_id}" }
    image_url { nil }
    venue_name { "Vega" }
    city { "Copenhagen" }
    country_code { "DK" }
    min_price_cents { 15_000 }
    currency { "DKK" }
    last_synced_at { Time.current }

    trait :past do
      starts_at { 3.days.ago.change(usec: 0) }
    end

    trait :free do
      min_price_cents { 0 }
    end
  end
end
