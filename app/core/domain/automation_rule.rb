module Core
  module Domain
    # Represents an automation rule in the system
    # An automation rule consists of a set of conditions and actions
    # When all conditions are met, the actions are executed
    class AutomationRule
      attr_reader :id, :name, :description, :conditions, :actions, :enabled, :created_at, :updated_at

      # Initialize a new automation rule
      # @param id [String] Unique identifier for the rule
      # @param name [String] Human-readable name for the rule
      # @param description [String] Detailed description of what the rule does
      # @param conditions [Array<Hash>] Conditions that must be met for the rule to trigger
      # @param actions [Array<Hash>] Actions to execute when conditions are met
      # @param enabled [Boolean] Whether the rule is currently active
      # @param created_at [Time] When the rule was created
      # @param updated_at [Time] When the rule was last updated
      def initialize(id:, name:, conditions:, actions:, description: nil, enabled: true, created_at: Time.now, updated_at: Time.now)
        @id = id
        @name = name
        @description = description
        @conditions = conditions
        @actions = actions
        @enabled = enabled
        @created_at = created_at
        @updated_at = updated_at

        validate!
      end

      # Evaluates all conditions and returns whether they are all satisfied
      # @param context [Hash] The evaluation context containing sensors and state data
      # @return [Boolean] True if all conditions are met, false otherwise
      def conditions_met?(context)
        return false unless enabled

        # All conditions must be met for the rule to trigger
        conditions.all? { |condition| evaluate_condition(condition, context) }
      end

      # Executes all actions defined in the rule
      # @param context [Hash] The execution context containing available actuators
      # @return [Array<Hash>] Results of each action execution
      def execute_actions(context)
        return [] unless enabled

        actions.map { |action| execute_action(action, context) }
      end

      # Evaluates a single condition
      # @param condition [Hash] The condition to evaluate
      # @param context [Hash] The evaluation context
      # @return [Boolean] Whether the condition is met
      def evaluate_condition(condition, context)
        entity_id = condition[:entity_id]
        attribute = condition[:attribute]
        operator = condition[:operator]
        value = condition[:value]

        return false unless context[:entities]&.key?(entity_id)

        entity = context[:entities][entity_id]
        current_value = entity[attribute]

        compare_values(current_value, operator, value)
      end

      # Executes a single action
      # @param action [Hash] The action to execute
      # @param context [Hash] The execution context
      # @return [Hash] The result of the action execution
      def execute_action(action, context)
        actuator_id = action[:actuator_id]
        command = action[:command].to_sym
        params = action[:params] || {}

        return { success: false, error: "Actuator not found: #{actuator_id}" } unless context[:actuators]&.key?(actuator_id)

        actuator = context[:actuators][actuator_id]

        unless actuator.supports_action?(command)
          return { success: false, error: "Unsupported action: #{command}" }
        end

        begin
          result = actuator.execute(params.merge(command: command))

          {
            success: result[:success],
            actuator_id: actuator_id,
            command: command,
            result: result
          }
        rescue => e
          {
            success: false,
            actuator_id: actuator_id,
            command: command,
            error: e.message
          }
        end
      end

      # Toggles the enabled state of the rule
      # @return [Boolean] The new enabled state
      def toggle_enabled
        @enabled = !@enabled
        @updated_at = Time.now
        @enabled
      end

      private

      # Compares two values using the specified operator
      # @param current_value [Object] The current value
      # @param operator [String] The comparison operator
      # @param target_value [Object] The target value to compare against
      # @return [Boolean] The result of the comparison
      def compare_values(current_value, operator, target_value)
        case operator
        when "eq", "=="
          current_value == target_value
        when "neq", "!="
          current_value != target_value
        when "gt", ">"
          current_value.to_f > target_value.to_f
        when "gte", ">="
          current_value.to_f >= target_value.to_f
        when "lt", "<"
          current_value.to_f < target_value.to_f
        when "lte", "<="
          current_value.to_f <= target_value.to_f
        when "contains"
          current_value.to_s.include?(target_value.to_s)
        when "not_contains"
          !current_value.to_s.include?(target_value.to_s)
        when "starts_with"
          current_value.to_s.start_with?(target_value.to_s)
        when "ends_with"
          current_value.to_s.end_with?(target_value.to_s)
        when "between"
          range = target_value.first.to_f..target_value.last.to_f
          range.include?(current_value.to_f)
        when "in"
          Array(target_value).include?(current_value)
        when "not_in"
          !Array(target_value).include?(current_value)
        when "present"
          !current_value.nil? && current_value != ""
        when "blank"
          current_value.nil? || current_value == ""
        else
          false
        end
      end

      def validate!
        raise ArgumentError, "ID cannot be empty" if id.nil? || id.empty?
        raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
        raise ArgumentError, "Conditions must be an array" unless conditions.is_a?(Array)
        raise ArgumentError, "Actions must be an array" unless actions.is_a?(Array)
        raise ArgumentError, "At least one condition is required" if conditions.empty?
        raise ArgumentError, "At least one action is required" if actions.empty?

        # Validate each condition has required fields
        conditions.each do |condition|
          unless condition.is_a?(Hash) && condition[:entity_id] && condition[:attribute] && condition[:operator]
            raise ArgumentError, "Each condition must have entity_id, attribute, and operator"
          end
        end

        # Validate each action has required fields
        actions.each do |action|
          unless action.is_a?(Hash) && action[:actuator_id] && action[:command]
            raise ArgumentError, "Each action must have actuator_id and command"
          end
        end
      end
    end
  end
end
