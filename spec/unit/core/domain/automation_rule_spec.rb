require "rails_helper"

RSpec.describe Domain::AutomationRule do
  let(:valid_id) { "rule-123" }
  let(:valid_name) { "Temperature Control Rule" }
  let(:valid_description) { "Turn on AC when temperature exceeds threshold" }
  let(:valid_conditions) do
    [
      { entity_id: "temp_sensor_1", attribute: "temperature", operator: "gt", value: 25 }
    ]
  end
  let(:valid_actions) do
    [
      { actuator_id: "hvac_1", command: "set_mode", params: { mode: "cooling" } }
    ]
  end

  let(:valid_attributes) do
    {
      id: valid_id,
      name: valid_name,
      description: valid_description,
      conditions: valid_conditions,
      actions: valid_actions,
      enabled: true
    }
  end

  describe "#initialize" do
    context "with valid attributes" do
      it "creates a new instance" do
        rule = described_class.new(**valid_attributes)

        expect(rule.id).to eq(valid_id)
        expect(rule.name).to eq(valid_name)
        expect(rule.description).to eq(valid_description)
        expect(rule.conditions).to eq(valid_conditions)
        expect(rule.actions).to eq(valid_actions)
        expect(rule.enabled).to be true
        expect(rule.created_at).to be_a(Time)
        expect(rule.updated_at).to be_a(Time)
      end

      it "sets default values for optional parameters" do
        rule = described_class.new(
          id: valid_id,
          name: valid_name,
          conditions: valid_conditions,
          actions: valid_actions
        )

        expect(rule.description).to be_nil
        expect(rule.enabled).to be true
        expect(rule.created_at).to be_a(Time)
        expect(rule.updated_at).to be_a(Time)
      end
    end

    context "with invalid attributes" do
      it "raises an error when id is missing" do
        expect do
          described_class.new(**valid_attributes, id: nil)
        end.to raise_error(ArgumentError, /ID cannot be empty/)
      end

      it "raises an error when name is missing" do
        expect do
          described_class.new(**valid_attributes, name: nil)
        end.to raise_error(ArgumentError, /Name cannot be empty/)
      end

      it "raises an error when conditions is missing" do
        expect do
          described_class.new(**valid_attributes.except(:conditions))
        end.to raise_error(ArgumentError)
      end

      it "raises an error when actions is missing" do
        expect do
          described_class.new(**valid_attributes.except(:actions))
        end.to raise_error(ArgumentError)
      end

      it "raises an error when conditions is empty" do
        expect do
          described_class.new(**valid_attributes, conditions: [])
        end.to raise_error(ArgumentError, /At least one condition is required/)
      end

      it "raises an error when actions is empty" do
        expect do
          described_class.new(**valid_attributes, actions: [])
        end.to raise_error(ArgumentError, /At least one action is required/)
      end

      it "raises an error when a condition is missing required fields" do
        invalid_condition = { entity_id: "sensor_1" } # missing attribute and operator
        expect do
          described_class.new(**valid_attributes, conditions: [invalid_condition])
        end.to raise_error(ArgumentError, /Each condition must have entity_id, attribute, and operator/)
      end

      it "raises an error when an action is missing required fields" do
        invalid_action = { actuator_id: "hvac_1" } # missing command
        expect do
          described_class.new(**valid_attributes, actions: [invalid_action])
        end.to raise_error(ArgumentError, /Each action must have actuator_id and command/)
      end
    end
  end

  describe "#conditions_met?" do
    let(:rule) { described_class.new(**valid_attributes) }
    let(:context) do
      {
        entities: {
          "temp_sensor_1" => { "temperature" => 26 }
        }
      }
    end

    context "when the rule is enabled" do
      it "returns true when all conditions are met" do
        expect(rule.conditions_met?(context)).to be true
      end

      it "returns false when any condition is not met" do
        context_with_lower_temp = {
          entities: {
            "temp_sensor_1" => { "temperature" => 24 }
          }
        }
        expect(rule.conditions_met?(context_with_lower_temp)).to be false
      end

      it "returns false when entity doesn't exist in context" do
        context_without_entity = { entities: {} }
        expect(rule.conditions_met?(context_without_entity)).to be false
      end
    end

    context "when the rule is disabled" do
      let(:disabled_rule) { described_class.new(**valid_attributes, enabled: false) }

      it "returns false even when conditions would be met" do
        expect(disabled_rule.conditions_met?(context)).to be false
      end
    end
  end

  describe "#execute_actions" do
    let(:rule) { described_class.new(**valid_attributes) }
    let(:actuator) { double("Actuator") }
    let(:context) do
      {
        actuators: {
          "hvac_1" => actuator
        }
      }
    end

    context "when the rule is enabled" do
      before do
        allow(actuator).to receive(:supports_action?).with(:set_mode).and_return(true)
        allow(actuator).to receive(:execute).and_return({ success: true, mode: "cooling" })
      end

      it "executes all actions" do
        results = rule.execute_actions(context)

        expect(results.length).to eq(1)
        expect(results[0][:success]).to be true
        expect(results[0][:actuator_id]).to eq("hvac_1")
        expect(results[0][:command]).to eq(:set_mode)
      end

      it "returns error when actuator doesn't exist in context" do
        context_without_actuator = { actuators: {} }
        results = rule.execute_actions(context_without_actuator)

        expect(results.length).to eq(1)
        expect(results[0][:success]).to be false
        expect(results[0][:error]).to include("Actuator not found")
      end

      it "returns error when action is not supported" do
        allow(actuator).to receive(:supports_action?).with(:set_mode).and_return(false)

        results = rule.execute_actions(context)

        expect(results.length).to eq(1)
        expect(results[0][:success]).to be false
        expect(results[0][:error]).to include("Unsupported action")
      end

      it "handles exceptions during execution" do
        allow(actuator).to receive(:execute).and_raise(StandardError.new("Test error"))

        results = rule.execute_actions(context)

        expect(results.length).to eq(1)
        expect(results[0][:success]).to be false
        expect(results[0][:error]).to eq("Test error")
      end
    end

    context "when the rule is disabled" do
      let(:disabled_rule) { described_class.new(**valid_attributes, enabled: false) }

      it "returns empty array without executing actions" do
        expect(actuator).not_to receive(:execute)

        results = disabled_rule.execute_actions(context)

        expect(results).to eq([])
      end
    end
  end

  describe "#toggle_enabled" do
    it "toggles from enabled to disabled" do
      rule = described_class.new(**valid_attributes, enabled: true)

      expect(rule.toggle_enabled).to be false
      expect(rule.enabled).to be false
    end

    it "toggles from disabled to enabled" do
      rule = described_class.new(**valid_attributes, enabled: false)

      expect(rule.toggle_enabled).to be true
      expect(rule.enabled).to be true
    end

    it "updates the updated_at timestamp" do
      rule = described_class.new(**valid_attributes)
      old_updated_at = rule.updated_at

      sleep(0.001) # Ensure time difference
      rule.toggle_enabled

      expect(rule.updated_at).to be > old_updated_at
    end
  end

  describe "#evaluate_condition" do
    let(:rule) { described_class.new(**valid_attributes) }

    it "returns false when entity does not exist" do
      context = { entities: {} }
      condition = { entity_id: "nonexistent", attribute: "value", operator: "eq", value: 42 }

      expect(rule.evaluate_condition(condition, context)).to be false
    end

    it "returns true when condition is met" do
      context = { entities: { "sensor" => { "temperature" => 30 } } }
      condition = { entity_id: "sensor", attribute: "temperature", operator: "gt", value: 25 }

      expect(rule.evaluate_condition(condition, context)).to be true
    end

    it "returns false when condition is not met" do
      context = { entities: { "sensor" => { "temperature" => 20 } } }
      condition = { entity_id: "sensor", attribute: "temperature", operator: "gt", value: 25 }

      expect(rule.evaluate_condition(condition, context)).to be false
    end

    it "handles context with nil entities" do
      context = {}
      condition = { entity_id: "sensor", attribute: "value", operator: "eq", value: 42 }

      expect(rule.evaluate_condition(condition, context)).to be false
    end
  end

  describe "#compare_values" do
    let(:rule) { described_class.new(**valid_attributes) }

    # Test private method
    it "compares values correctly with eq operator" do
      result = rule.send(:compare_values, 5, "eq", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "==", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "eq", 10)
      expect(result).to be false
    end

    it "compares values correctly with neq operator" do
      result = rule.send(:compare_values, 5, "neq", 10)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "!=", 10)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "neq", 5)
      expect(result).to be false
    end

    it "compares values correctly with gt operator" do
      result = rule.send(:compare_values, 10, "gt", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 10, ">", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "gt", 10)
      expect(result).to be false
    end

    it "compares values correctly with gte operator" do
      result = rule.send(:compare_values, 10, "gte", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 5, ">=", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "gte", 10)
      expect(result).to be false
    end

    it "compares values correctly with lt operator" do
      result = rule.send(:compare_values, 5, "lt", 10)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "<", 10)
      expect(result).to be true

      result = rule.send(:compare_values, 10, "lt", 5)
      expect(result).to be false
    end

    it "compares values correctly with lte operator" do
      result = rule.send(:compare_values, 5, "lte", 10)
      expect(result).to be true

      result = rule.send(:compare_values, 5, "<=", 5)
      expect(result).to be true

      result = rule.send(:compare_values, 10, "lte", 5)
      expect(result).to be false
    end

    it "compares values correctly with contains operator" do
      result = rule.send(:compare_values, "hello world", "contains", "world")
      expect(result).to be true

      result = rule.send(:compare_values, "hello", "contains", "world")
      expect(result).to be false
    end

    it "compares values correctly with not_contains operator" do
      result = rule.send(:compare_values, "hello", "not_contains", "world")
      expect(result).to be true

      result = rule.send(:compare_values, "hello world", "not_contains", "world")
      expect(result).to be false
    end

    it "compares values correctly with starts_with operator" do
      result = rule.send(:compare_values, "hello world", "starts_with", "hello")
      expect(result).to be true

      result = rule.send(:compare_values, "hello world", "starts_with", "world")
      expect(result).to be false
    end

    it "compares values correctly with ends_with operator" do
      result = rule.send(:compare_values, "hello world", "ends_with", "world")
      expect(result).to be true

      result = rule.send(:compare_values, "hello world", "ends_with", "hello")
      expect(result).to be false
    end

    it "compares values correctly with between operator" do
      result = rule.send(:compare_values, 15, "between", [10, 20])
      expect(result).to be true

      result = rule.send(:compare_values, 5, "between", [10, 20])
      expect(result).to be false
    end

    it "compares values correctly with in operator" do
      result = rule.send(:compare_values, "b", "in", ["a", "b", "c"])
      expect(result).to be true

      result = rule.send(:compare_values, "x", "in", ["a", "b", "c"])
      expect(result).to be false
    end

    it "compares values correctly with not_in operator" do
      result = rule.send(:compare_values, "x", "not_in", ["a", "b", "c"])
      expect(result).to be true

      result = rule.send(:compare_values, "b", "not_in", ["a", "b", "c"])
      expect(result).to be false
    end

    it "compares values correctly with present operator" do
      result = rule.send(:compare_values, "hello", "present", nil)
      expect(result).to be true

      result = rule.send(:compare_values, nil, "present", nil)
      expect(result).to be false

      result = rule.send(:compare_values, "", "present", nil)
      expect(result).to be false
    end

    it "compares values correctly with blank operator" do
      result = rule.send(:compare_values, nil, "blank", nil)
      expect(result).to be true

      result = rule.send(:compare_values, "", "blank", nil)
      expect(result).to be true

      result = rule.send(:compare_values, "hello", "blank", nil)
      expect(result).to be false
    end

    it "returns false for unknown operators" do
      result = rule.send(:compare_values, 5, "unknown_operator", 10)
      expect(result).to be false
    end
  end
end
