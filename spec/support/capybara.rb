require "capybara/rspec"
require "capybara/cuprite"

# Headless Chrome through the Chrome DevTools Protocol (no chromedriver needed).
# HEADLESS=false bin/rspec spec/system to watch the browser.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1280, 900 ],
    headless: ENV["HEADLESS"] != "false",
    process_timeout: 30,
    timeout: 15,
    js_errors: true,
    # The test-suite must never reach the internet (fake Clerk is served by the app itself).
    url_blocklist: [ %r{\Ahttps?://(?!127\.0\.0\.1|localhost)} ],
    browser_options: ENV["CI"] || File.exist?("/.dockerenv") ? { "no-sandbox" => nil } : {}
  )
end

Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite
  end
end
