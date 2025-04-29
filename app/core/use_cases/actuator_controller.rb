module Core
  module UseCases
    # ActuatorController is responsible for managing collections of actuators
    # and coordinating their actions based on incoming commands.
    class ActuatorController
      attr_reader :actuators

      def initialize
        @actuators = {}
      end

      # Register a new actuator with the controller
      # @param actuator [Core::Domain::Actuator] The actuator to register
      # @return [Boolean] True if registration was successful
      def register(actuator)
        unless actuator.is_a?(Core::Domain::Actuator)
          raise ArgumentError, "Only actuators can be registered"
        end

        if @actuators[actuator.name]
          raise ArgumentError, "An actuator with name '#{actuator.name}' is already registered"
        end

        @actuators[actuator.name] = actuator
        true
      end

      # Unregister an actuator from the controller
      # @param name [String] The name of the actuator to unregister
      # @return [Boolean] True if unregistration was successful
      def unregister(name)
        if @actuators.delete(name)
          true
        else
          false
        end
      end

      # Find actuators by criteria
      # @param criteria [Hash] A hash of criteria to search for (e.g. location: 'kitchen')
      # @return [Array<Core::Domain::Actuator>] Array of matching actuators
      def find_actuators(criteria = {})
        return @actuators.values if criteria.empty?

        @actuators.values.select do |actuator|
          criteria.all? do |key, value|
            if key == :name
              actuator.name == value
            elsif actuator.respond_to?(key)
              actuator.send(key) == value
            elsif actuator.properties.key?(key)
              actuator.properties[key] == value
            else
              false
            end
          end
        end
      end

      # Execute an action on a specific actuator
      # @param actuator_name [String] The name of the actuator to use
      # @param action_params [Hash] Parameters for the action
      # @return [Hash] The result of the action
      def execute_action(actuator_name, action_params)
        actuator = @actuators[actuator_name]

        unless actuator
          return {
            success: false,
            error: "Actuator '#{actuator_name}' not found"
          }
        end

        begin
          result = actuator.execute(action_params)
          result.merge(actuator_name: actuator_name)
        rescue ArgumentError => e
          {
            success: false,
            actuator_name: actuator_name,
            error: e.message
          }
        rescue StandardError => e
          {
            success: false,
            actuator_name: actuator_name,
            error: "Execution error: #{e.message}"
          }
        end
      end

      # Execute actions on multiple actuators matching criteria
      # @param criteria [Hash] Criteria for selecting actuators
      # @param action_params [Hash] Parameters for the action
      # @return [Array<Hash>] Results from each actuator
      def execute_group_action(criteria, action_params)
        actuators = find_actuators(criteria)

        if actuators.empty?
          return [{
            success: false,
            error: "No actuators found matching criteria: #{criteria}"
          }]
        end

        actuators.map do |actuator|
          begin
            result = actuator.execute(action_params)
            result.merge(actuator_name: actuator.name)
          rescue ArgumentError => e
            {
              success: false,
              actuator_name: actuator.name,
              error: e.message
            }
          rescue StandardError => e
            {
              success: false,
              actuator_name: actuator.name,
              error: "Execution error: #{e.message}"
            }
          end
        end
      end

      # Execute an action on all actuators of a specific type
      # @param actuator_type [Class] The class of actuator to target
      # @param action_params [Hash] Parameters for the action
      # @return [Array<Hash>] Results from each actuator
      def execute_type_action(actuator_type, action_params)
        actuators = @actuators.values.select { |a| a.is_a?(actuator_type) }

        if actuators.empty?
          return [{
            success: false,
            error: "No actuators found of type: #{actuator_type}"
          }]
        end

        actuators.map do |actuator|
          begin
            result = actuator.execute(action_params)
            result.merge(actuator_name: actuator.name)
          rescue ArgumentError => e
            {
              success: false,
              actuator_name: actuator.name,
              error: e.message
            }
          rescue StandardError => e
            {
              success: false,
              actuator_name: actuator.name,
              error: "Execution error: #{e.message}"
            }
          end
        end
      end
    end
  end
end
