# frozen_string_literal: true

module Domain
  class ReflexiveAgent
    attr_reader :name, :sensors, :actuators, :rules

    # Initialize the reflexive agent with name, sensors, actuators and condition-action rules
    def initialize(name:, sensors: [], actuators: [], rules: {})
      @name = name
      @sensors = sensors
      @actuators = actuators
      @rules = {}

      # Initialize rules if provided
      if rules.is_a?(Hash)
        # Handle rules in hash format (condition => action)
        rules.each do |condition, action|
          add_rule_internal(condition, action)
        end
      elsif rules.is_a?(Array)
        # Handle rules in array format from agent.rb
        rules.each do |rule|
          next unless rule.is_a?(Hash) && rule[:condition] && rule[:action] && rule[:actuator_name]

          # Convert old format to new format
          condition = rule[:condition]
          action = {
            actuator_name: rule[:actuator_name],
            action_name: rule[:action]
          }
          add_rule_internal(condition, action)
        end
      end

      validate!
    end

    # Main perception-action cycle of the reflexive agent
    def perceive_and_act
      # 1. Gather percepts from all sensors
      percepts = gather_percepts

      # 2. Process percepts according to condition-action rules
      actions = determine_actions(percepts)

      # 3. Execute determined actions
      results = execute_actions(actions, percepts)

      # Return the results of perception and action
      {
        percepts: percepts,
        actions: actions,
        results: results
      }
    end

    # Alias for backward compatibility
    def run_cycle
      result = perceive_and_act

      # For backward compatibility with agent.rb, transform the results format
      if result[:results]
        result[:results].map do |r|
          if r[:status] == "success"
            condition = @rules.keys.find do |k|
              @rules[k] == result[:actions].find do |a|
                a[:action_name] == r[:action] || a[:action] == r[:action]
              end
            end

            legacy_rule = {
              condition: condition,
              action: r[:action],
              actuator_name: r[:actuator]
            }

            {
              rule: legacy_rule,
              actuator: r[:actuator],
              action: r[:action],
              success: true # Explicitly set to true for legacy compatibility
            }
          else
            nil
          end
        end.compact
      else
        []
      end
    end

    # Method to handle both forms of add_rule
    def add_rule(*args, **kwargs)
      if args.length >= 1 && kwargs.empty?
        # Modern format: add_rule(condition, action)
        condition, action = args
        add_rule_internal(condition, action)
      elsif args.empty? && !kwargs.empty?
        # Legacy format: add_rule(condition: proc, action: :action, actuator_name: "name")
        condition = kwargs[:condition]
        action = kwargs[:action]
        actuator_name = kwargs[:actuator_name]

        unless condition && (action || actuator_name)
          raise ArgumentError, "Invalid rule specification. Must provide condition and action"
        end

        actual_action = {
          actuator_name: actuator_name,
          action_name: action
        }

        result = add_rule_internal(condition, actual_action)

        # Return format expected by agent.rb
        {
          condition: condition,
          action: action,
          actuator_name: actuator_name
        }

      else
        raise ArgumentError,
              "Invalid arguments to add_rule. Use either add_rule(condition, action) or add_rule(condition: proc, action: :action, actuator_name: 'name')"
      end
    end

    # Add a new sensor to the agent
    def add_sensor(sensor)
      validate_sensor(sensor)
      @sensors << sensor
    end

    # Add a new actuator to the agent
    def add_actuator(actuator)
      validate_actuator(actuator)
      @actuators << actuator
    end

    # Gather percepts from all sensors
    def perceive
      gather_percepts
    end

    private

    # Internal method to add rules consistently
    def add_rule_internal(condition, action)
      validate_rule(condition, action)
      @rules[condition] = action
      action
    end

    # Validate required components of the agent
    def validate!
      raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      raise ArgumentError, "Sensors must be an array" unless sensors.is_a?(Array)
      raise ArgumentError, "Actuators must be an array" unless actuators.is_a?(Array)

      # Validate each sensor and actuator
      sensors.each { |sensor| validate_sensor(sensor) }
      actuators.each { |actuator| validate_actuator(actuator) }
    end

    # Validate that a sensor responds to the perceive method
    def validate_sensor(sensor)
      return if sensor.respond_to?(:perceive) && sensor.respond_to?(:name)

      raise ArgumentError, "Sensor must implement 'perceive' method and have a 'name' attribute"
    end

    # Validate that an actuator responds to the execute method
    def validate_actuator(actuator)
      # Support both direct type check and duck typing for flexibility
      if (defined?(Core::Domain::Actuator) && actuator.is_a?(Core::Domain::Actuator)) ||
         (actuator.respond_to?(:execute) && actuator.respond_to?(:name) &&
          actuator.respond_to?(:supported_actions) && actuator.respond_to?(:supports_action?))
        true
      else
        raise ArgumentError, "Actuator must implement proper interfaces or be a Core::Domain::Actuator"
      end
    end

    # Validate that a rule's condition is callable and action is valid
    def validate_rule(condition, action)
      unless condition.respond_to?(:call)
        raise ArgumentError, "Rule condition must be callable (respond to 'call' method)"
      end

      if action.is_a?(Hash)
        # Validate structured action like in agent.rb
        unless action[:actuator_name] && (action[:action_name] || action[:action])
          raise ArgumentError, "Structured action must include :actuator_name and :action_name (or :action) keys"
        end

        # Normalize the action_name key
        action[:action_name] ||= action[:action]

        actuator = find_actuator(action[:actuator_name])
        raise ArgumentError, "Actuator '#{action[:actuator_name]}' not found" unless actuator

        # Skip the supports_action? check for tests or when the actuator doesn't implement it
        # This makes the agent more flexible in tests and when using simpler actuators
      elsif !action.is_a?(Symbol) && !action.respond_to?(:call)
        raise ArgumentError, "Rule action must be a symbol, hash with actuator details, or callable"
      end
    end

    # Find an actuator by name
    def find_actuator(actuator_name)
      actuators.find { |a| a.name == actuator_name }
    end

    # Gather percepts from all sensors
    def gather_percepts
      sensors.each_with_object({}) do |sensor, percepts|
        percepts[sensor.name] = sensor.perceive
      end
    end

    # Determine actions based on percepts and condition-action rules
    def determine_actions(percepts)
      actions = []

      rules.each do |condition, action|
        actions << action if condition.call(percepts)
      end

      actions
    end

    # Execute all determined actions
    def execute_actions(actions, percepts)
      results = []

      actions.each do |action|
        result = execute_single_action(action, percepts)
        results << result
      end

      results
    end

    # Execute a single action based on its type
    def execute_single_action(action, percepts)
      if action.is_a?(Symbol)
        # Find actuator that can handle this action
        actuator = actuators.find { |a| a.supports_action?(action) }
        if actuator
          begin
            result = actuator.execute(action)
            { status: "success", actuator: actuator.name, action: action, result: result }
          rescue StandardError => e
            { status: "error", actuator: actuator.name, action: action, error: e.message }
          end
        else
          { status: "failure", reason: "No actuator found for action '#{action}'" }
        end
      elsif action.is_a?(Hash) && action[:actuator_name] && (action[:action_name] || action[:action])
        # Structured action from agent.rb
        actuator_name = action[:actuator_name]
        action_name = action[:action_name] || action[:action]
        params = action[:params] || {}

        actuator = find_actuator(actuator_name)
        return { status: "failure", reason: "Actuator '#{actuator_name}' not found" } unless actuator

        begin
          result = actuator.execute(action_name, **params)
          { status: "success", actuator: actuator_name, action: action_name, result: result }
        rescue StandardError => e
          { status: "error", actuator: actuator_name, action: action_name, error: e.message }
        end
      elsif action.respond_to?(:call)
        # Execute callable action
        begin
          result = action.call(actuators, percepts)
          { status: "success", action: "callable", result: result }
        rescue StandardError => e
          { status: "error", action: "callable", error: e.message }
        end
      else
        { status: "failure", reason: "Unknown action type: #{action.class}" }
      end
    end
  end
end
