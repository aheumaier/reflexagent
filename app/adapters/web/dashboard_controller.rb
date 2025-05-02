# frozen_string_literal: true

require_relative "../../ports/dashboard_port"
module Web
  class DashboardController < ApplicationController
    include DashboardPort

    def index
      # Dashboard view
      render
    end

    def update_dashboard_with_metric(metric)
      # Implementation of DashboardPort#update_dashboard_with_metric
      # Will update dashboard via Hotwire in a real implementation
      true
    end

    def update_dashboard_with_alert(alert)
      # Implementation of DashboardPort#update_dashboard_with_alert
      # Will update dashboard via Hotwire in a real implementation
      true
    end
  end
end
