module Command
  # Rejects invalid commands before any transaction is opened.
  class ValidatingBus
    def initialize(next_bus)
      @next_bus = next_bus
    end

    def call(command)
      command.validate!
      @next_bus.call(command)
    end
  end
end
