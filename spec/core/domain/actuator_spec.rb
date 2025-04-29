require 'rails_helper'
require_relative '../../../app/core/domain/actuator'

RSpec.describe Core::Domain::Actuator do
  let(:valid_name) { "test_actuator" }
  let(:valid_properties) { { location: "living_room" } }

  describe "#initialize" do
    it "requires a name" do
      expect { described_class.new(properties: valid_properties) }.to raise_error(ArgumentError)
    end

    it "raises error when name is empty" do
      expect { described_class.new(name: "", **valid_properties) }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "sets name and properties" do
      actuator = described_class.new(name: valid_name, **valid_properties)
      expect(actuator.name).to eq(valid_name)
      expect(actuator.properties).to include(valid_properties)
    end
  end

  describe "#execute" do
    it "raises NotImplementedError in base class" do
      actuator = described_class.new(name: valid_name, **valid_properties)
      expect { actuator.execute({}) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement execute method"
      )
    end
  end

  describe "#supported_actions" do
    it "raises NotImplementedError in base class" do
      actuator = described_class.new(name: valid_name, **valid_properties)
      expect { actuator.supported_actions }.to raise_error(
        NotImplementedError,
        "Subclasses must implement supported_actions method"
      )
    end
  end

  describe "#supports_action?" do
    let(:test_actuator_class) do
      Class.new(described_class) do
        def supported_actions
          [:turn_on, :turn_off]
        end
      end
    end

    let(:actuator) { test_actuator_class.new(name: valid_name, **valid_properties) }

    it "returns true when action is supported" do
      expect(actuator.supports_action?(:turn_on)).to be true
    end

    it "returns false when action is not supported" do
      expect(actuator.supports_action?(:invalid_action)).to be false
    end
  end

  describe "#validate_required_params" do
    let(:actuator) { described_class.new(name: valid_name, **valid_properties) }
    let(:params) { { param1: "value1", param2: "value2" } }

    it "doesn't raise error when all required params are present" do
      expect { actuator.validate_required_params(params, [:param1, :param2]) }.not_to raise_error
    end

    it "raises ArgumentError when required params are missing" do
      expect {
        actuator.validate_required_params(params, [:param1, :param3])
      }.to raise_error(ArgumentError, "Missing required parameters: param3")
    end

    it "raises ArgumentError listing all missing params" do
      expect {
        actuator.validate_required_params(params, [:param3, :param4])
      }.to raise_error(ArgumentError, "Missing required parameters: param3, param4")
    end
  end

  describe "Base Actuator" do
    it "validates name presence" do
      expect { Core::Domain::Actuator.new(name: "") }.to raise_error(ArgumentError, "Name cannot be empty")
      expect { Core::Domain::Actuator.new(name: nil) }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "stores additional properties" do
      actuator = Core::Domain::Actuator.new(name: "TestActuator", color: "blue", priority: "high")
      expect(actuator.properties).to include(color: "blue", priority: "high")
    end
  end

  describe Core::Domain::HvacActuator do
    let(:valid_params) do
      {
        name: "Living Room HVAC",
        device_id: "hvac-001",
        location: "living-room",
        default_temperature: 22.0
      }
    end

    it "initializes with required parameters" do
      actuator = Core::Domain::HvacActuator.new(**valid_params)
      expect(actuator.name).to eq("Living Room HVAC")
      expect(actuator.device_id).to eq("hvac-001")
      expect(actuator.location).to eq("living-room")
      expect(actuator.properties[:default_temperature]).to eq(22.0)
    end

    it "validates device_id presence" do
      invalid_params = valid_params.merge(device_id: "")
      expect { Core::Domain::HvacActuator.new(**invalid_params) }.to raise_error(ArgumentError, "Device ID cannot be empty")
    end

    it "validates location presence" do
      invalid_params = valid_params.merge(location: "")
      expect { Core::Domain::HvacActuator.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end

    it "performs heating action" do
      actuator = Core::Domain::HvacActuator.new(**valid_params)
      result = actuator.execute(mode: :heat, temperature: 25.0)

      expect(result[:success]).to be true
      expect(result[:mode]).to eq(:heat)
      expect(result[:target_temperature]).to eq(25.0)
      expect(result[:result]).to include("Heating to 25.0")
    end

    it "performs cooling action" do
      actuator = Core::Domain::HvacActuator.new(**valid_params)
      result = actuator.execute(mode: :cool, temperature: 18.0)

      expect(result[:success]).to be true
      expect(result[:mode]).to eq(:cool)
      expect(result[:target_temperature]).to eq(18.0)
      expect(result[:result]).to include("Cooling to 18.0")
    end

    it "validates action parameters" do
      actuator = Core::Domain::HvacActuator.new(**valid_params)

      expect { actuator.execute("not_a_hash") }.to raise_error(ArgumentError, "Action parameters must be a hash")
      expect { actuator.execute(mode: :invalid) }.to raise_error(ArgumentError, /Mode must be one of/)
      expect { actuator.execute(mode: :heat) }.to raise_error(ArgumentError, /Temperature must be provided/)
    end
  end

  describe Core::Domain::LightActuator do
    let(:valid_params) do
      {
        name: "Bedroom Light",
        location: "bedroom",
        default_brightness: 70
      }
    end

    it "initializes with required parameters" do
      actuator = Core::Domain::LightActuator.new(**valid_params)
      expect(actuator.name).to eq("Bedroom Light")
      expect(actuator.location).to eq("bedroom")
      expect(actuator.properties[:default_brightness]).to eq(70)
    end

    it "validates location presence" do
      invalid_params = valid_params.merge(location: "")
      expect { Core::Domain::LightActuator.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end

    it "turns light on" do
      actuator = Core::Domain::LightActuator.new(**valid_params)
      result = actuator.execute(command: :on)

      expect(result[:success]).to be true
      expect(result[:command]).to eq(:on)
      expect(result[:result]).to include("Light turned on")
    end

    it "dims light to specified brightness" do
      actuator = Core::Domain::LightActuator.new(**valid_params)
      result = actuator.execute(command: :dim, brightness: 30)

      expect(result[:success]).to be true
      expect(result[:command]).to eq(:dim)
      expect(result[:brightness]).to eq(30)
      expect(result[:result]).to include("Light dimmed to 30%")
    end

    it "validates action parameters" do
      actuator = Core::Domain::LightActuator.new(**valid_params)

      expect { actuator.execute(command: :invalid) }.to raise_error(ArgumentError, /Command must be one of/)
      expect { actuator.execute(command: :dim, brightness: 101) }.to raise_error(ArgumentError, /Brightness must be/)
      expect { actuator.execute(command: :dim, brightness: -1) }.to raise_error(ArgumentError, /Brightness must be/)
    end
  end

  describe Core::Domain::DoorActuator do
    let(:valid_params) do
      {
        name: "Front Door",
        door_id: "door-001",
        location: "entrance",
        default_locked: true
      }
    end

    it "initializes with required parameters" do
      actuator = Core::Domain::DoorActuator.new(**valid_params)
      expect(actuator.name).to eq("Front Door")
      expect(actuator.door_id).to eq("door-001")
      expect(actuator.location).to eq("entrance")
      expect(actuator.properties[:default_locked]).to eq(true)
    end

    it "validates door_id presence" do
      invalid_params = valid_params.merge(door_id: "")
      expect { Core::Domain::DoorActuator.new(**invalid_params) }.to raise_error(ArgumentError, "Door ID cannot be empty")
    end

    it "validates location presence" do
      invalid_params = valid_params.merge(location: "")
      expect { Core::Domain::DoorActuator.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end

    it "locks the door" do
      actuator = Core::Domain::DoorActuator.new(**valid_params)
      result = actuator.execute(command: :lock)

      expect(result[:success]).to be true
      expect(result[:command]).to eq(:lock)
      expect(result[:result]).to include("Door locked successfully")
    end

    it "unlocks the door" do
      actuator = Core::Domain::DoorActuator.new(**valid_params)
      result = actuator.execute(command: :unlock)

      expect(result[:success]).to be true
      expect(result[:command]).to eq(:unlock)
      expect(result[:result]).to include("Door unlocked successfully")
    end

    it "validates action parameters" do
      actuator = Core::Domain::DoorActuator.new(**valid_params)

      expect { actuator.execute("not_a_hash") }.to raise_error(ArgumentError, "Action parameters must be a hash")
      expect { actuator.execute(command: :invalid) }.to raise_error(ArgumentError, /Command must be one of/)
    end
  end
end

# Test classes for testing the base Actuator class
class TestActuator < Core::Domain::Actuator
end

class TestActuatorWithActions < Core::Domain::Actuator
  def supported_actions
    [:test_action]
  end

  def execute(params)
    # Override to avoid NotImplementedError
    { success: true }
  end
end
