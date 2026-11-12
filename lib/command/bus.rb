module Command
  # Innermost link of the chain: resolves the handler of a command and executes it.
  class Bus
    def initialize
      @handlers = Concurrent::Map.new
    end

    def register(command_class, handler)
      raise ArgumentError, "#{command_class} already registered" if @handlers.key?(command_class.name)

      @handlers[command_class.name] = handler
      self
    end

    def call(command)
      if command.is_a?(Command::Executable)
        command.call
      else
        handler = @handlers[command.class.name] or raise UnregisteredCommand, "no handler for #{command.class.name}"
        handler.respond_to?(:call) ? handler.call(command) : handler.new.call(command)
      end
    end

    def registered?(command_class) = @handlers.key?(command_class.name)
  end
end
