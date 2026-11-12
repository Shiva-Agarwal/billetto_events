class ApplicationController < ActionController::Base
  include Authentication
  include CommandBusInjector

  protect_from_forgery with: :exception
end
