module Handler
  class AsyncJob < ActiveJob::Base
    include EventStoreInjector

    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 12

    def perform(handler_name, event_id)
      fact = event_store.read.event!(event_id)
      handler_name.constantize.handle(fact)
    end
  end
end
