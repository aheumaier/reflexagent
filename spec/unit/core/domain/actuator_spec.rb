require "rails_helper"

# Load our specific implementation rather than any mock version
RSpec.describe Domain::Actuator do
  # Force reload the implementation directly from the file
  before do
    # Save the current implementation if it exists
    @original_actuator = Domain::Actuator if defined?(Domain::Actuator)

    # Reload our implementation
    load Rails.root.join("app/core/domain/actuator.rb")

    # Store the freshly loaded implementation
    @actuator_class = Domain::Actuator
  end

  # Restore original implementation after each test to avoid breaking other tests
  after do
    if defined?(@original_actuator)
      Domain.send(:remove_const, :Actuator)
      Domain.const_set(:Actuator, @original_actuator)
    end
  end

  let(:valid_name) { "test_actuator" }
  let(:valid_properties) { { location: "living_room" } }

  describe "#initialize" do
    it "requires a name" do
      expect { @actuator_class.new(properties: valid_properties) }.to raise_error(ArgumentError)
    end

    it "raises error when name is empty" do
      expect { @actuator_class.new(name: "", **valid_properties) }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "sets name and properties" do
      actuator = @actuator_class.new(name: valid_name, **valid_properties)
      expect(actuator.name).to eq(valid_name)
      expect(actuator.properties).to include(valid_properties)
    end
  end

  describe "#execute" do
    it "raises NotImplementedError in base class" do
      actuator = @actuator_class.new(name: valid_name, **valid_properties)
      expect { actuator.execute({}) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement execute method"
      )
    end
  end

  describe "#supported_actions" do
    it "raises NotImplementedError in base class" do
      actuator = @actuator_class.new(name: valid_name, **valid_properties)
      expect { actuator.supported_actions }.to raise_error(
        NotImplementedError,
        "Subclasses must implement supported_actions method"
      )
    end
  end

  describe "#supports_action?" do
    let(:test_actuator_class) do
      Class.new(@actuator_class) do
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
    let(:actuator) { @actuator_class.new(name: valid_name, **valid_properties) }
    let(:params) { { param1: "value1", param2: "value2" } }

    it "doesn't raise error when all required params are present" do
      expect { actuator.validate_required_params(params, [:param1, :param2]) }.not_to raise_error
    end

    it "raises ArgumentError when required params are missing" do
      expect do
        actuator.validate_required_params(params, [:param1, :param3])
      end.to raise_error(ArgumentError, "Missing required parameters: param3")
    end

    it "raises ArgumentError listing all missing params" do
      expect do
        actuator.validate_required_params(params, [:param3, :param4])
      end.to raise_error(ArgumentError, "Missing required parameters: param3, param4")
    end
  end

  describe "Base Actuator" do
    it "validates name presence" do
      expect { @actuator_class.new(name: "") }.to raise_error(ArgumentError, "Name cannot be empty")
      expect { @actuator_class.new(name: nil) }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "stores additional properties" do
      actuator = @actuator_class.new(name: "TestActuator", color: "blue", priority: "high")
      expect(actuator.properties).to include(color: "blue", priority: "high")
    end
  end
end
