# Commands are plain, validated value objects expressing an intent ("cast a vote").
# They are ONLY executed by sending them to the command bus (Rails.configuration.command_bus),
# never called directly, so every execution gets the same cross-cutting concerns
# (validation, instrumentation, transaction, correlation/causation ids) - see lib/command/*.rb.
#
# Two flavours, as in the Developer's Guide:
#
#   * Command::Executable - self executing command (GoF command pattern), for simple use-cases.
#   * Command::Handler    - a service object handling one or more (plain) commands, for use-cases
#                           with dependencies or shared logic; registered in ApplicationCommandBus.
module Command
  Error = Class.new(StandardError)
  UnregisteredCommand = Class.new(Error)

  class Invalid < Error
    attr_reader :command, :errors

    def initialize(command)
      @command = command
      @errors = command.errors
      super("#{command.class.name} is invalid: #{errors.full_messages.to_sentence}")
    end
  end

  # Typed attributes + ActiveModel validations.
  #
  #   attribute :event_tid, String
  #   attribute :events, Array, default: -> { [] }
  module Base
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    COERCIONS = {
      String => ->(value) { value.nil? ? nil : value.to_s.strip.presence },
      Integer => ->(value) { value.nil? || value == "" ? nil : Integer(value, exception: false) || value },
      Array => ->(value) { value.nil? ? nil : Array(value) },
      Hash => ->(value) { value.nil? ? nil : value.to_h },
      :boolean => ->(value) { ActiveModel::Type::Boolean.new.cast(value) }
    }.freeze

    included do
      class_attribute :attribute_definitions, instance_writer: false, default: {}
    end

    class_methods do
      def attribute(name, type, default: nil)
        self.attribute_definitions = attribute_definitions.merge(name.to_sym => { type: type, default: default })
        attr_reader name
      end
    end

    def initialize(**attributes)
      unknown = attributes.keys.map(&:to_sym) - attribute_definitions.keys
      raise ArgumentError, "#{self.class.name}: unknown attributes #{unknown.inspect}" if unknown.any?

      attribute_definitions.each do |name, definition|
        value = attributes.fetch(name) { definition[:default].respond_to?(:call) ? definition[:default].call : definition[:default] }
        coercion = COERCIONS.fetch(definition[:type]) { ->(v) { v } }
        instance_variable_set(:"@#{name}", coercion.call(value))
      end
      super()
    end

    def to_h = attribute_definitions.keys.index_with { |name| public_send(name) }

    def validate! = valid? || raise(Command::Invalid, self)

    def inspect = "#<#{self.class.name} #{to_h.inspect}>"
  end

  module Executable
    extend ActiveSupport::Concern
    include Base
    include EventStoreInjector
    include CommandBusInjector

    # Executable commands "self-register": the bus recognises them and invokes #call.
    def call
      raise NotImplementedError, "#{self.class.name}#call"
    end
  end

  module Handler
    extend ActiveSupport::Concern
    include EventStoreInjector
    include CommandBusInjector

    included do
      class_attribute :command_routes, instance_writer: false, default: {}
    end

    class_methods do
      def handles(command_class, method_name)
        self.command_routes = command_routes.merge(command_class => method_name)
      end

      def handled_commands = command_routes.keys
    end

    def handled_commands = self.class.handled_commands

    def call(command)
      method_name = command_routes.fetch(command.class) do
        raise UnregisteredCommand, "#{self.class.name} does not handle #{command.class.name}"
      end
      send(method_name, command)
    end
  end
end
