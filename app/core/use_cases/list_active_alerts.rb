# frozen_string_literal: true

module UseCases
  # ListActiveAlerts retrieves current active alerts and formats them for dashboard display
  class ListActiveAlerts
    def initialize(storage_port:, cache_port: nil)
      @storage_port = storage_port
      @cache_port = cache_port
    end

    # @param time_period [Integer] The number of days to look back
    # @param limit [Integer] Maximum number of alerts to return
    # @param severity [String, nil] Optional severity filter
    # @return [Array<Hash>] Formatted alerts for display
    def call(time_period:, limit: 5, severity: nil)
      # Implementation will be added later
      []
    end

    private

    # Get cache key for storing active alerts
    # @param time_period [Integer] Time period in days
    # @param limit [Integer] Result limit
    # @param severity [String, nil] Severity filter
    # @return [String] Cache key
    def cache_key(time_period, limit, severity)
      parts = ["active_alerts"]
      parts << "days_#{time_period}"
      parts << "limit_#{limit}"
      parts << severity if severity
      parts.join(":")
    end
  end
end
