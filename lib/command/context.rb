module Command
  # Fiber/thread-local "fact being handled right now".
  module Context
    KEY = :command_context_current_fact

    module_function

    def current_fact = ActiveSupport::IsolatedExecutionState[KEY]

    def with_fact(fact)
      previous = current_fact
      ActiveSupport::IsolatedExecutionState[KEY] = fact
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = previous
    end
  end
end
