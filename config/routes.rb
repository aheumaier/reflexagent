Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Custom health check endpoint for Render
  get "health" => "health#index"

  # API routes
  namespace :api do
    namespace :v1 do
      # Events - Unified webhook endpoint
      # Accepts source parameter to identify the webhook source
      # Example: POST /api/v1/events?source=github
      resources :events, only: [:create, :show]

      # Metrics
      resources :metrics, only: [:index, :show] do
        member do
          post :analyze # Endpoint to detect anomalies
        end
      end

      # Alerts
      resources :alerts, only: [:index, :show] do
        member do
          post :notify # Endpoint to send notifications
        end
      end
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
