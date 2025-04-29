module Core
  module UseCases
    class FindAlert
      def initialize(storage_port:)
        @storage_port = storage_port
      end

      def call(id)
        alert = @storage_port.find_alert(id)
        raise ArgumentError, "Alert with ID '#{id}' not found" if alert.nil?
        alert
      end
    end
  end
end
