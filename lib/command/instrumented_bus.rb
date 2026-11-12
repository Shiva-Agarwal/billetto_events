module Command
  # Publishes `call.command_bus` notifications (timing, command class, exception) that are
  # picked up by logging / APM subscribers (see config/initializers/instrumentation.rb).
  class InstrumentedBus
    EVENT = "call.command_bus".freeze

    def initialize(next_bus, notifications: ActiveSupport::Notifications)
      @next_bus = next_bus
      @notifications = notifications
    end

    def call(command)
      @notifications.instrument(EVENT, command: command, command_name: command.class.name) do
        @next_bus.call(command)
      end
    end
  end
end
