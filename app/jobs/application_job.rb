class ApplicationJob < ActiveJob::Base
  include EventStoreInjector
  include CommandBusInjector

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
