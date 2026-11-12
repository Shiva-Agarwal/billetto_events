require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.cache_store = :memory_store
  else
    config.action_controller.perform_caching = false
    config.cache_store = :memory_store # needed by rate_limit + JWKS cache
  end

  # No Redis needed locally: async jobs run in-process unless ACTIVE_JOB_ADAPTER is set.
  config.active_job.queue_adapter = ENV.fetch("ACTIVE_JOB_ADAPTER", "async").to_sym

  # Without real credentials, run against in-memory fakes (each integration independently).
  config.x.fake_billetto = ENV.fetch("FAKE_BILLETTO") { ENV.fetch("FAKE_INTEGRATIONS") { ENV["BILLETTO_API_KEYPAIR"].blank?.to_s } } == "true"
  config.x.fake_clerk = ENV.fetch("FAKE_CLERK") { ENV.fetch("FAKE_INTEGRATIONS") { ENV["CLERK_PUBLISHABLE_KEY"].blank?.to_s } } == "true"

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.active_record.query_log_tags_enabled = true
  config.active_job.verbose_enqueue_logs = true
  config.action_view.annotate_rendered_view_with_filenames = true
  config.action_controller.raise_on_missing_callback_actions = true
end
