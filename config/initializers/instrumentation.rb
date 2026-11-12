# Structured log line per command executed through the command bus.
ActiveSupport::Notifications.subscribe("call.command_bus") do |event|
  payload = event.payload
  status = payload[:exception] ? "failed (#{payload[:exception].first})" : "ok"
  Rails.logger.info("[command_bus] #{payload[:command_name]} #{status} in #{event.duration.round(1)}ms")
end

ActiveSupport::Notifications.subscribe("import.catalog") do |event|
  Rails.logger.info("[catalog.import] #{event.payload.except(:rejections).inspect}")
end
