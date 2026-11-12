source "https://rubygems.org"

gem "rails", "~> 8.0"
gem "pg", "~> 1.5"
gem "puma", ">= 6.0"
gem "propshaft"
gem "bootsnap", require: false

# Event-driven architecture
gem "rails_event_store", "~> 2.15"

# Background processing (production ActiveJob adapter, same stack as Billetto)
gem "sidekiq", "~> 7.3"

# HTTP client for 3rd party integrations (Billetto, Clerk JWKS)
gem "faraday", "~> 2.12"
gem "faraday-retry", "~> 2.2"

# Clerk session token (JWT) verification
gem "jwt", "~> 2.9"

group :development, :test do
  gem "debug", platforms: %i[mri], require: "debug/prelude"
  gem "dotenv-rails", "~> 3.1"
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "ruby_event_store-rspec", "~> 2.15"
  gem "webmock", "~> 3.24"
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.15"
  gem "simplecov", require: false
end
