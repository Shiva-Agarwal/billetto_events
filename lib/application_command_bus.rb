# Builds the application command bus as a chain of responsibility:
#
#   Instrumented -> Validating -> Correlation -> Transactional -> Bus (dispatch)
#
# and registers handlers of non-executable commands. Executable commands need no registration.
module ApplicationCommandBus
  module_function

  def build(event_store:)
    bus = Command::Bus.new
    register_commands(bus)

    Command::InstrumentedBus.new(
      Command::ValidatingBus.new(
        Command::CorrelationBus.new(
          Command::TransactionalBus.new(bus),
          event_store: event_store
        )
      )
    )
  end

  def register_commands(bus)
    catalog = Catalog::Service.new
    catalog.handled_commands.each { |command| bus.register(command, catalog) }

    identity = Identity::Service.new
    identity.handled_commands.each { |command| bus.register(command, identity) }
  end
end
