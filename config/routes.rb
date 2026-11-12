Rails.application.routes.draw do
  root "events#index"

  resources :events, only: :index do
    resource :vote, only: %i[create destroy], module: :events
  end

  get "sign_in", to: "auth#sign_in"
  get "sign_up", to: "auth#sign_up"

  post "webhooks/clerk", to: "webhooks/clerk#create"

  get "up", to: "rails/health#show", as: :rails_health_check

  if Rails.configuration.x.fake_clerk
    get "__fake_clerk/clerk.js", to: "fake_clerk#script", as: :fake_clerk_script
  end

  if Rails.env.development?
    require "ruby_event_store/browser/app"
    # Rails Event Store browser: inspect streams, facts, correlation/causation chains.
    mount RubyEventStore::Browser::App.for(event_store_locator: -> { Rails.configuration.event_store.client }) => "/res"
  end
end
