# Serves the fake clerk-js used when FAKE_CLERK is on (tests / local dev without Clerk).
# Only routed when fake integrations are enabled.
class FakeClerkController < ActionController::Base
  # Static, non-sensitive JS loaded via <script src>: exempt from Rails' cross-origin JS protection.
  skip_forgery_protection
  def script
    send_file Rails.root.join("vendor/fake_clerk/clerk.js"), type: "text/javascript", disposition: "inline"
  end
end
