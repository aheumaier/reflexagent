module Core
  module Domain
    # Base class for all actuators in the system
    class Actuator
      attr_reader :name, :properties

      # Initialize a new actuator
      # @param name [String] Unique identifier for the actuator
      # @param properties [Hash] Custom properties of the actuator
      def initialize(name:, **properties)
        raise ArgumentError, "Name cannot be empty" if name.nil? || name.to_s.empty?
        @name = name
        @properties = properties
      end

      # Execute an action on this actuator
      # @param params [Hash] Action parameters
      # @return [Hash] A result hash containing :success and other relevant information
      def execute(params)
        raise NotImplementedError, "Subclasses must implement execute method"
      end

      # Returns the actions supported by this actuator
      # @return [Array<Symbol>] List of supported action keys
      def supported_actions
        raise NotImplementedError, "Subclasses must implement supported_actions method"
      end

      # Checks if the actuator supports a specific action
      # @param action [Symbol] The action to check
      # @return [Boolean] True if the action is supported, false otherwise
      def supports_action?(action)
        supported_actions.include?(action)
      end

      # Validates that required parameters are present
      # @param params [Hash] The parameters to validate
      # @param required [Array<Symbol>] List of required parameter keys
      # @raise [ArgumentError] If any required parameters are missing
      def validate_required_params(params, required)
        missing = required.select { |param| params[param].nil? }
        return if missing.empty?

        raise ArgumentError, "Missing required parameters: #{missing.join(', ')}"
      end
    end
  end
end
