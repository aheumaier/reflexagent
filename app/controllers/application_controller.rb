class ApplicationController < ActionController::Base
  # Helper method to get the dashboard adapter from the dependency container
  # This provides a consistent way for all controllers to access the dashboard adapter
  # @return [Dashboard::DashboardAdapter] The dashboard adapter instance
  def dashboard_adapter
    @dashboard_adapter ||= DependencyContainer.resolve(:dashboard_adapter)
  end

  # Helper method to safely call dashboard adapter methods with standardized error handling
  # @param method_name [Symbol] The name of the method to call on the dashboard adapter
  # @param fallback [Object] The fallback value to return if an error occurs
  # @param args [Hash] The arguments to pass to the method
  # @return [Object] The result of the method call or the fallback value if an error occurs
  def with_dashboard_adapter(method_name, fallback, **args)
    dashboard_adapter.public_send(method_name, **args)
  rescue StandardError => e
    Rails.logger.error("Error calling dashboard adapter method '#{method_name}': #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    fallback
  end
end
