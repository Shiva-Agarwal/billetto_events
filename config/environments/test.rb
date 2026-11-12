require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }
  config.consider_all_requests_local = true
  config.cache_store = :null_store
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.active_support.deprecation = :stderr
  config.action_controller.raise_on_missing_callback_actions = true

  config.active_job.queue_adapter = :test

  # The test-suite never talks to Billetto or Clerk: fake adapters are wired instead
  # (see config/initializers/integrations.rb), as recommended by the Developer's Guide.
  config.x.fake_billetto = true
  config.x.fake_clerk = true
end
