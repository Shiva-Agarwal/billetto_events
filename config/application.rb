require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module BillettoEvents
  class Application < Rails::Application
    config.load_defaults 8.0

    # lib/ holds framework-level building blocks (Fact, Command bus, Handler, ...)
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Async read models / integrators / jobs run through ActiveJob.
    # Production: Sidekiq. Development: in-process :async (no Redis needed) unless overridden.
    config.active_job.queue_adapter = ENV.fetch("ACTIVE_JOB_ADAPTER", "sidekiq").to_sym

    # When true, the app wires in-memory fake adapters instead of the real 3rd party APIs
    # (used by the test suite and for running the app without credentials).
    boolean = ActiveModel::Type::Boolean.new
    config.x.fake_billetto = boolean.cast(ENV.fetch("FAKE_BILLETTO", ENV.fetch("FAKE_INTEGRATIONS", "false")))
    config.x.fake_clerk = boolean.cast(ENV.fetch("FAKE_CLERK", ENV.fetch("FAKE_INTEGRATIONS", "false")))

    config.generators do |g|
      g.test_framework :rspec
      g.orm :active_record
    end
  end
end
