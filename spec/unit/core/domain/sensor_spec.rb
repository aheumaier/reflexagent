require "rails_helper"

RSpec.describe Domain::Sensor do
  describe "#initialize" do
    it "sets name and properties" do
      sensor = described_class.new(name: "test_sensor", unit: "celsius")
      expect(sensor.name).to eq("test_sensor")
      expect(sensor.properties).to eq({ unit: "celsius" })
    end

    it "raises error when name is empty" do
      expect { described_class.new(name: "") }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it "raises error when name is nil" do
      expect { described_class.new(name: nil) }.to raise_error(ArgumentError, "Name cannot be empty")
    end
  end

  describe "#perceive" do
    it "raises NotImplementedError in base class" do
      sensor = described_class.new(name: "test_sensor")
      expect { sensor.perceive }.to raise_error(NotImplementedError, "Domain::Sensor must implement #perceive")
    end
  end
end

RSpec.describe Domain::TemperatureSensor do
  let(:valid_params) do
    {
      name: "temp_sensor_1",
      device_id: "dev123",
      location: "kitchen",
      unit: "celsius"
    }
  end

  describe "#initialize" do
    it "sets all attributes correctly" do
      sensor = described_class.new(**valid_params)
      expect(sensor.name).to eq("temp_sensor_1")
      expect(sensor.device_id).to eq("dev123")
      expect(sensor.location).to eq("kitchen")
      expect(sensor.properties).to eq({ unit: "celsius" })
    end

    it "raises error when device_id is empty" do
      invalid_params = valid_params.merge(device_id: "")
      expect { described_class.new(**invalid_params) }.to raise_error(ArgumentError, "Device ID cannot be empty")
    end

    it "raises error when location is empty" do
      invalid_params = valid_params.merge(location: "")
      expect { described_class.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end
  end

  describe "#perceive" do
    let(:sensor) { described_class.new(**valid_params) }
    let(:current_time) { Time.new(2023, 1, 1, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(current_time)
      # Mock the random temperature generation
      allow(sensor).to receive(:fetch_current_temperature).and_return(23.5)
    end

    it "returns a hash with temperature data" do
      result = sensor.perceive
      expect(result).to be_a(Hash)
      expect(result[:temperature]).to eq(23.5)
      expect(result[:unit]).to eq("celsius")
      expect(result[:timestamp]).to eq(current_time)
      expect(result[:location]).to eq("kitchen")
    end

    it "uses the unit from properties if specified" do
      custom_sensor = described_class.new(**valid_params, unit: "fahrenheit")
      allow(custom_sensor).to receive(:fetch_current_temperature).and_return(74.3)

      result = custom_sensor.perceive
      expect(result[:unit]).to eq("fahrenheit")
    end
  end
end

RSpec.describe Domain::MotionSensor do
  let(:valid_params) do
    {
      name: "motion_sensor_1",
      location: "hallway",
      sensitivity: :medium
    }
  end

  describe "#initialize" do
    it "sets all attributes correctly" do
      sensor = described_class.new(**valid_params)
      expect(sensor.name).to eq("motion_sensor_1")
      expect(sensor.location).to eq("hallway")
      expect(sensor.sensitivity).to eq(:medium)
    end

    it "raises error when location is empty" do
      invalid_params = valid_params.merge(location: "")
      expect { described_class.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end

    it "raises error when sensitivity is invalid" do
      invalid_params = valid_params.merge(sensitivity: :ultra_high)
      expect do
        described_class.new(**invalid_params)
      end.to raise_error(ArgumentError, "Sensitivity must be one of: low, medium, high")
    end

    it "defaults to medium sensitivity when not specified" do
      params_without_sensitivity = valid_params.except(:sensitivity)
      sensor = described_class.new(**params_without_sensitivity)
      expect(sensor.sensitivity).to eq(:medium)
    end
  end

  describe "#perceive" do
    let(:sensor) { described_class.new(**valid_params) }
    let(:current_time) { Time.new(2023, 1, 1, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(current_time)
    end

    context "when motion is detected" do
      before do
        allow(sensor).to receive(:detect_motion).and_return(true)
      end

      it "returns a hash with motion detected" do
        result = sensor.perceive
        expect(result).to be_a(Hash)
        expect(result[:motion_detected]).to eq(true)
        expect(result[:location]).to eq("hallway")
        expect(result[:sensitivity]).to eq(:medium)
        expect(result[:timestamp]).to eq(current_time)
      end
    end

    context "when no motion is detected" do
      before do
        allow(sensor).to receive(:detect_motion).and_return(false)
      end

      it "returns a hash with no motion detected" do
        result = sensor.perceive
        expect(result).to be_a(Hash)
        expect(result[:motion_detected]).to eq(false)
      end
    end
  end
end

RSpec.describe Domain::LightSensor do
  let(:valid_params) do
    {
      name: "light_sensor_1",
      location: "living_room"
    }
  end

  describe "#initialize" do
    it "sets all attributes correctly" do
      sensor = described_class.new(**valid_params)
      expect(sensor.name).to eq("light_sensor_1")
      expect(sensor.location).to eq("living_room")
    end

    it "raises error when location is empty" do
      invalid_params = valid_params.merge(location: "")
      expect { described_class.new(**invalid_params) }.to raise_error(ArgumentError, "Location cannot be empty")
    end
  end

  describe "#perceive" do
    let(:sensor) { described_class.new(**valid_params) }
    let(:current_time) { Time.new(2023, 1, 1, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(current_time)
      # Mock the light level measurement
      allow(sensor).to receive(:measure_light_level).and_return(75)
    end

    it "returns a hash with light level data" do
      result = sensor.perceive
      expect(result).to be_a(Hash)
      expect(result[:light_level]).to eq(75)
      expect(result[:location]).to eq("living_room")
      expect(result[:timestamp]).to eq(current_time)
    end
  end

  describe "#measure_light_level" do
    let(:sensor) { described_class.new(**valid_params) }

    context "during daytime" do
      it "returns a value between 50 and 100" do
        # Set time to noon
        allow(Time).to receive_message_chain(:now, :hour).and_return(12)

        # Mock rand to return a specific value in the daytime range
        allow(sensor).to receive(:rand).with(50..100).and_return(75)

        expect(sensor.send(:measure_light_level)).to eq(75)
      end
    end

    context "during nighttime" do
      it "returns a value between 0 and 30" do
        # Set time to midnight
        allow(Time).to receive_message_chain(:now, :hour).and_return(0)

        # Mock rand to return a specific value in the nighttime range
        allow(sensor).to receive(:rand).with(0..30).and_return(15)

        expect(sensor.send(:measure_light_level)).to eq(15)
      end
    end
  end
end
