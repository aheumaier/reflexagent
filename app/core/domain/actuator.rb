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

    # HVAC control actuator for heating, cooling, and ventilation
    class HvacActuator < Actuator
      attr_reader :device_id, :location

      VALID_MODES = [:heat, :cool, :fan, :off]

      def initialize(name:, device_id:, location:, **properties)
        @device_id = device_id
        @location = location
        @target_temperature = properties[:default_temperature] || 22.0
        super(name: name, **properties)
      end

      def execute(params)
        validate_params!(params)

        mode = params[:mode]
        temperature = params[:temperature]

        case mode
        when :heat
          {
            success: true,
            mode: mode,
            target_temperature: temperature,
            result: "Heating to #{temperature}"
          }
        when :cool
          {
            success: true,
            mode: mode,
            target_temperature: temperature,
            result: "Cooling to #{temperature}"
          }
        when :fan
          {
            success: true,
            mode: mode,
            result: "Fan mode activated"
          }
        when :off
          {
            success: true,
            mode: mode,
            result: "System turned off"
          }
        end
      end

      def supported_actions
        VALID_MODES
      end

      private

      def validate_params!(params)
        unless params.is_a?(Hash)
          raise ArgumentError, "Action parameters must be a hash"
        end

        mode = params[:mode]
        unless VALID_MODES.include?(mode)
          raise ArgumentError, "Mode must be one of: #{VALID_MODES.join(', ')}"
        end

        if [:heat, :cool].include?(mode) && !params[:temperature]
          raise ArgumentError, "Temperature must be provided for heating or cooling"
        end
      end
    end

    # Light control actuator
    class LightActuator < Actuator
      attr_reader :location

      VALID_COMMANDS = [:on, :off, :dim]

      def initialize(name:, location:, **properties)
        @location = location
        super(name: name, **properties)
      end

      def execute(params)
        validate_params!(params)

        command = params[:command]
        brightness = params[:brightness]

        case command
        when :on
          {
            success: true,
            command: command,
            result: "Light turned on"
          }
        when :off
          {
            success: true,
            command: command,
            result: "Light turned off"
          }
        when :dim
          {
            success: true,
            command: command,
            brightness: brightness,
            result: "Light dimmed to #{brightness}%"
          }
        end
      end

      def supported_actions
        VALID_COMMANDS
      end

      private

      def validate_params!(params)
        unless params.is_a?(Hash)
          raise ArgumentError, "Action parameters must be a hash"
        end

        command = params[:command]
        unless VALID_COMMANDS.include?(command)
          raise ArgumentError, "Command must be one of: #{VALID_COMMANDS.join(', ')}"
        end

        if command == :dim
          brightness = params[:brightness]
          unless brightness.is_a?(Integer) && brightness >= 0 && brightness <= 100
            raise ArgumentError, "Brightness must be an integer between 0 and 100"
          end
        end
      end
    end

    # Door control actuator
    class DoorActuator < Actuator
      attr_reader :door_id, :location

      VALID_COMMANDS = [:lock, :unlock]

      def initialize(name:, door_id:, location:, **properties)
        @door_id = door_id
        @location = location
        super(name: name, **properties)
      end

      def execute(params)
        validate_params!(params)

        command = params[:command]

        case command
        when :lock
          {
            success: true,
            command: command,
            result: "Door locked successfully"
          }
        when :unlock
          {
            success: true,
            command: command,
            result: "Door unlocked successfully"
          }
        end
      end

      def supported_actions
        VALID_COMMANDS
      end

      private

      def validate_params!(params)
        unless params.is_a?(Hash)
          raise ArgumentError, "Action parameters must be a hash"
        end

        command = params[:command]
        unless VALID_COMMANDS.include?(command)
          raise ArgumentError, "Command must be one of: #{VALID_COMMANDS.join(', ')}"
        end
      end
    end
  end
end
