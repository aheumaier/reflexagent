require "sidekiq/web" # require the web UI

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Custom health check endpoint for Render
  get "health" => "health#index"

  # Mount Sidekiq web UI
  mount Sidekiq::Web => "/sidekiq" # access it at http://localhost:3000/sidekiq

  # Dashboard routes
  get "dashboards/engineering", to: "dashboards#engineering", as: :engineering_dashboard

  # API routes
  namespace :api do
    namespace :v1 do
      # Events - Unified webhook endpoint
      # Accepts source parameter to identify the webhook source
      # Example: POST /api/v1/events?source=github
      resources :events, only: [:create, :index, :show]

      # Metrics
      resources :metrics, only: [:index, :show]

      # Alerts
      resources :alerts, only: [:index, :show]
    end
  end

  # Defines the root path route ("/")
  root "rails/health#show"
end
