require "rails_helper"

# We need to define a mock Sensor class first

module Core
  module Domain
    unless defined?(Domain::Sensor)
      class Sensor
        attr_reader :name, :properties

        def initialize(name:, **properties)
          @name = name
          @properties = properties
        end

        def perceive
          {}
        end
      end
    end
    # Mock Actuator for this test only - it needs to match the signature of our real Actuator
    unless defined?(Domain::Actuator)
      class Actuator
        attr_reader :name, :properties

        def initialize(name:, **properties)
          @name = name
          @properties = properties
        end

        def execute(params)
          true
        end

        def supported_actions
          []
        end

        def supports_action?(action_name)
          true
        end
      end
    end
  end
end

RSpec.describe Domain::ReflexiveAgent do
  let(:test_sensor) { Domain::Sensor.new(name: "test_sensor") }
  let(:test_actuator) { Domain::Actuator.new(name: "test_actuator") }

  before do
    # Make the test_sensor return useful data
    allow(test_sensor).to receive(:perceive).and_return({ "temperature" => 25 })

    # Configure the test_actuator
    allow(test_actuator).to receive(:supported_actions).and_return([:turn_on, :turn_off])
    allow(test_actuator).to receive(:supports_action?).with(:turn_on).and_return(true)
    allow(test_actuator).to receive(:supports_action?).with(:turn_off).and_return(true)
    allow(test_actuator).to receive(:supports_action?).with(any_args).and_return(false)
    allow(test_actuator).to receive(:execute).with(any_args).and_return(true)
  end

  describe "#initialize" do
    it "creates an agent with empty collections when no arguments are provided" do
      agent = described_class.new(name: "test_agent")
      expect(agent.name).to eq("test_agent")
      expect(agent.sensors).to be_empty
      expect(agent.actuators).to be_empty
      expect(agent.rules).to be_empty
    end

    it "initializes with provided sensors and actuators" do
      agent = described_class.new(
        name: "test_agent",
        sensors: [test_sensor],
        actuators: [test_actuator]
      )
      expect(agent.sensors).to contain_exactly(test_sensor)
      expect(agent.actuators).to contain_exactly(test_actuator)
    end
  end

  describe "#add_rule" do
    let(:agent) { described_class.new(name: "test_agent", actuators: [test_actuator]) }
    let(:condition) { ->(percepts) { percepts["test_sensor"]["temperature"] > 20 } }

    context "when using the legacy interface (agent.rb)" do
      it "adds a rule with named parameters" do
        result = agent.add_rule(
          condition: condition,
          action: :turn_on,
          actuator_name: "test_actuator"
        )

        expect(result).to be_a(Hash)
        expect(result[:condition]).to eq(condition)
        expect(result[:action]).to eq(:turn_on)
        expect(result[:actuator_name]).to eq("test_actuator")
      end
    end

    context "when using the new interface (reflexive_agent.rb)" do
      it "adds a rule with positional parameters" do
        action = { actuator_name: "test_actuator", action_name: :turn_on }
        agent.add_rule(condition, action)

        # Check if the rule was added by running a cycle that would match
        agent.add_sensor(test_sensor)
        result = agent.perceive_and_act

        expect(result[:actions]).to include(action)
        expect(result[:results].first[:status]).to eq("success")
      end
    end
  end

  describe "#run_cycle" do
    let(:agent) { described_class.new(name: "test_agent", sensors: [test_sensor], actuators: [test_actuator]) }
    let(:condition) { ->(percepts) { percepts["test_sensor"]["temperature"] > 20 } }

    before do
      agent.add_rule(
        condition: condition,
        action: :turn_on,
        actuator_name: "test_actuator"
      )
    end

    it "returns results in the legacy format" do
      results = agent.run_cycle

      expect(results).to be_an(Array)
      expect(results.size).to eq(1)
      expect(results.first[:actuator]).to eq("test_actuator")
      expect(results.first[:action]).to eq(:turn_on)
      expect(results.first[:success]).to eq(true)
    end
  end

  describe "#perceive_and_act" do
    let(:agent) { described_class.new(name: "test_agent", sensors: [test_sensor], actuators: [test_actuator]) }
    let(:condition) { ->(percepts) { percepts["test_sensor"]["temperature"] > 20 } }

    before do
      action = { actuator_name: "test_actuator", action_name: :turn_on }
      agent.add_rule(condition, action)
    end

    it "returns results in the new detailed format" do
      result = agent.perceive_and_act

      expect(result).to be_a(Hash)
      expect(result).to have_key(:percepts)
      expect(result).to have_key(:actions)
      expect(result).to have_key(:results)
      expect(result[:results].first[:status]).to eq("success")
      expect(result[:results].first[:actuator]).to eq("test_actuator")
    end
  end
end
