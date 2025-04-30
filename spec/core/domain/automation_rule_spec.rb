require 'rails_helper'

# RSpec.describe Core::Domain::AutomationRule do
#   let(:valid_id) { "rule-123" }
#   let(:valid_name) { "Temperature Control Rule" }
#   let(:valid_description) { "Turn on AC when temperature exceeds threshold" }
#   let(:valid_conditions) do
#     [
#       { entity_id: "temp_sensor_1", attribute: "temperature", operator: "gt", value: 25 }
#     ]
#   end
#   let(:valid_actions) do
#     [
#       { actuator_id: "hvac_1", command: "set_mode", params: { mode: "cooling" } }
#     ]
#   end

#   let(:valid_attributes) do
#     {
#       id: valid_id,
#       name: valid_name,
#       description: valid_description,
#       conditions: valid_conditions,
#       actions: valid_actions,
#       enabled: true
#     }
#   end

#   describe "#initialize" do
#     context "with valid attributes" do
#       it "creates a new instance" do
#         rule = described_class.new(valid_attributes)

#         expect(rule.id).to eq(valid_id)
#         expect(rule.name).to eq(valid_name)
#         expect(rule.description).to eq(valid_description)
#         expect(rule.conditions).to eq(valid_conditions)
#         expect(rule.actions).to eq(valid_actions)
#         expect(rule.enabled).to be true
#         expect(rule.created_at).to be_a(Time)
#         expect(rule.updated_at).to be_a(Time)
#       end

#       it "sets default values for optional parameters" do
#         rule = described_class.new(
#           id: valid_id,
#           name: valid_name,
#           conditions: valid_conditions,
#           actions: valid_actions
#         )

#         expect(rule.description).to be_nil
#         expect(rule.enabled).to be true
#         expect(rule.created_at).to be_a(Time)
#         expect(rule.updated_at).to be_a(Time)
#       end
#     end

#     context "with invalid attributes" do
#       it "raises an error when id is missing" do
#         expect {
#           described_class.new(valid_attributes.except(:id))
#         }.to raise_error(ArgumentError, /ID cannot be empty/)
#       end

#       it "raises an error when name is missing" do
#         expect {
#           described_class.new(valid_attributes.except(:name))
#         }.to raise_error(ArgumentError, /Name cannot be empty/)
#       end

#       it "raises an error when conditions is missing" do
#         expect {
#           described_class.new(valid_attributes.except(:conditions))
#         }.to raise_error(ArgumentError)
#       end

#       it "raises an error when actions is missing" do
#         expect {
#           described_class.new(valid_attributes.except(:actions))
#         }.to raise_error(ArgumentError)
#       end

#       it "raises an error when conditions is empty" do
#         expect {
#           described_class.new(valid_attributes.merge(conditions: []))
#         }.to raise_error(ArgumentError, /At least one condition is required/)
#       end

#       it "raises an error when actions is empty" do
#         expect {
#           described_class.new(valid_attributes.merge(actions: []))
#         }.to raise_error(ArgumentError, /At least one action is required/)
#       end

#       it "raises an error when a condition is missing required fields" do
#         invalid_condition = { entity_id: "sensor_1" } # missing attribute and operator
#         expect {
#           described_class.new(valid_attributes.merge(conditions: [invalid_condition]))
#         }.to raise_error(ArgumentError, /Each condition must have entity_id, attribute, and operator/)
#       end

#       it "raises an error when an action is missing required fields" do
#         invalid_action = { actuator_id: "hvac_1" } # missing command
#         expect {
#           described_class.new(valid_attributes.merge(actions: [invalid_action]))
#         }.to raise_error(ArgumentError, /Each action must have actuator_id and command/)
#       end
#     end
#   end

#   describe "#conditions_met?" do
#     let(:rule) { described_class.new(valid_attributes) }
#     let(:context) do
#       {
#         entities: {
#           "temp_sensor_1" => { "temperature" => 26 }
#         }
#       }
#     end

#     context "when the rule is enabled" do
#       it "returns true when all conditions are met" do
#         expect(rule.conditions_met?(context)).to be true
#       end

#       it "returns false when any condition is not met" do
#         context_with_lower_temp = {
#           entities: {
#             "temp_sensor_1" => { "temperature" => 24 }
#           }
#         }
#         expect(rule.conditions_met?(context_with_lower_temp)).to be false
#       end

#       it "returns false when entity doesn't exist in context" do
#         context_without_entity = { entities: {} }
#         expect(rule.conditions_met?(context_without_entity)).to be false
#       end
#     end

#     context "when the rule is disabled" do
#       let(:disabled_rule) { described_class.new(valid_attributes.merge(enabled: false)) }

#       it "returns false even when conditions would be met" do
#         expect(disabled_rule.conditions_met?(context)).to be false
#       end
#     end
#   end

#   describe "#execute_actions" do
#     let(:rule) { described_class.new(valid_attributes) }
#     let(:actuator) { double("Actuator") }
#     let(:context) do
#       {
#         actuators: {
#           "hvac_1" => actuator
#         }
#       }
#     end

#     context "when the rule is enabled" do
#       before do
#         allow(actuator).to receive(:supports_action?).with(:set_mode).and_return(true)
#         allow(actuator).to receive(:execute).and_return({ success: true, mode: "cooling" })
#       end

#       it "executes all actions" do
#         results = rule.execute_actions(context)

#         expect(results.length).to eq(1)
#         expect(results[0][:success]).to be true
#         expect(results[0][:actuator_id]).to eq("hvac_1")
#         expect(results[0][:command]).to eq(:set_mode)
#       end

#       it "returns error when actuator doesn't exist in context" do
#         context_without_actuator = { actuators: {} }
#         results = rule.execute_actions(context_without_actuator)

#         expect(results.length).to eq(1)
#         expect(results[0][:success]).to be false
#         expect(results[0][:error]).to include("Actuator not found")
#       end

#       it "returns error when action is not supported" do
#         allow(actuator).to receive(:supports_action?).with(:set_mode).and_return(false)

#         results = rule.execute_actions(context)

#         expect(results.length).to eq(1)
#         expect(results[0][:success]).to be false
#         expect(results[0][:error]).to include("Unsupported action")
#       end

#       it "handles exceptions during execution" do
#         allow(actuator).to receive(:execute).and_raise(StandardError.new("Test error"))

#         results = rule.execute_actions(context)

#         expect(results.length).to eq(1)
#         expect(results[0][:success]).to be false
#         expect(results[0][:error]).to eq("Test error")
#       end
#     end

#     context "when the rule is disabled" do
#       let(:disabled_rule) { described_class.new(valid_attributes.merge(enabled: false)) }

#       it "returns empty array without executing actions" do
#         expect(actuator).not_to receive(:execute)

#         results = disabled_rule.execute_actions(context)

#         expect(results).to eq([])
#       end
#     end
#   end

#   describe "#toggle_enabled" do
#     it "toggles from enabled to disabled" do
#       rule = described_class.new(valid_attributes.merge(enabled: true))

#       expect(rule.toggle_enabled).to be false
#       expect(rule.enabled).to be false
#     end

#     it "toggles from disabled to enabled" do
#       rule = described_class.new(valid_attributes.merge(enabled: false))

#       expect(rule.toggle_enabled).to be true
#       expect(rule.enabled).to be true
#     end

#     it "updates the updated_at timestamp" do
#       rule = described_class.new(valid_attributes)
#       old_updated_at = rule.updated_at

#       sleep(0.001) # Ensure time difference
#       rule.toggle_enabled

#       expect(rule.updated_at).to be > old_updated_at
#     end
#   end

#   describe "#compare_values" do
#     let(:rule) { described_class.new(valid_attributes) }

#     context "with equality operators" do
#       it "correctly evaluates eq operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "eq", value: 10 }
#         context = { entities: { "sensor" => { "value" => 10 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 11 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end

#       it "correctly evaluates neq operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "neq", value: 10 }
#         context = { entities: { "sensor" => { "value" => 11 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 10 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end

#     context "with numeric comparison operators" do
#       it "correctly evaluates gt operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "gt", value: 10 }
#         context = { entities: { "sensor" => { "value" => 11 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 10 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end

#       it "correctly evaluates lt operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "lt", value: 10 }
#         context = { entities: { "sensor" => { "value" => 9 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 10 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end

#     context "with string operators" do
#       it "correctly evaluates contains operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "contains", value: "abc" }
#         context = { entities: { "sensor" => { "value" => "xabcy" } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => "xyz" } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end

#       it "correctly evaluates starts_with operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "starts_with", value: "abc" }
#         context = { entities: { "sensor" => { "value" => "abcxyz" } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => "xyzabc" } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end

#     context "with collection operators" do
#       it "correctly evaluates in operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "in", value: [1, 2, 3] }
#         context = { entities: { "sensor" => { "value" => 2 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 4 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end

#       it "correctly evaluates between operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "between", value: [10, 20] }
#         context = { entities: { "sensor" => { "value" => 15 } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => 25 } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end

#     context "with presence operators" do
#       it "correctly evaluates present operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "present", value: nil }
#         context = { entities: { "sensor" => { "value" => "something" } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => nil } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end

#       it "correctly evaluates blank operator" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "blank", value: nil }
#         context = { entities: { "sensor" => { "value" => nil } } }

#         expect(rule.evaluate_condition(condition, context)).to be true

#         context = { entities: { "sensor" => { "value" => "something" } } }
#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end

#     context "with invalid operator" do
#       it "returns false for unsupported operators" do
#         condition = { entity_id: "sensor", attribute: "value", operator: "invalid_op", value: 10 }
#         context = { entities: { "sensor" => { "value" => 10 } } }

#         expect(rule.evaluate_condition(condition, context)).to be false
#       end
#     end
#   end
# end
