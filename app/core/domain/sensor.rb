module Core
  module Domain
    # Base class for all sensors that provide percepts about the environment
    class Sensor
      attr_reader :name, :properties

      def initialize(name:, **properties)
        @name = name
        @properties = properties

        validate!
      end

      # Abstract method to be implemented by concrete sensors
      # Returns the current perception of the environment
      def perceive
        raise NotImplementedError, "#{self.class.name} must implement #perceive"
      end

      private

      def validate!
        raise ArgumentError, "Name cannot be empty" if name.nil? || name.empty?
      end
    end

    # Temperature sensor that can detect ambient temperature
    class TemperatureSensor < Sensor
      attr_reader :device_id, :location

      def initialize(name:, device_id:, location:, **properties)
        @device_id = device_id
        @location = location
        super(name: name, **properties)
      end

      def perceive
        reading = fetch_current_temperature
        {
          temperature: reading,
          unit: properties[:unit] || 'celsius',
          timestamp: Time.now,
          location: location
        }
      end

      private

      def validate!
        super
        raise ArgumentError, "Device ID cannot be empty" if device_id.nil? || device_id.empty?
        raise ArgumentError, "Location cannot be empty" if location.nil? || location.empty?
      end

      # Simulated temperature reading
      # In a real application, this would connect to an actual device
      def fetch_current_temperature
        # Simulate a temperature reading between 18 and 28 degrees
        rand(18.0..28.0).round(1)
      end
    end

    # Motion sensor that can detect movement in a specific area
    class MotionSensor < Sensor
      attr_reader :location, :sensitivity

      def initialize(name:, location:, sensitivity: :medium, **properties)
        @location = location
        @sensitivity = sensitivity
        super(name: name, **properties)
      end

      def perceive
        motion_detected = detect_motion
        {
          motion_detected: motion_detected,
          location: location,
          sensitivity: sensitivity,
          timestamp: Time.now
        }
      end

      private

      def validate!
        super
        raise ArgumentError, "Location cannot be empty" if location.nil? || location.empty?
        valid_sensitivities = [:low, :medium, :high]
        unless valid_sensitivities.include?(sensitivity)
          raise ArgumentError, "Sensitivity must be one of: #{valid_sensitivities.join(', ')}"
        end
      end

      # Simulated motion detection
      # In a real application, this would connect to an actual device
      def detect_motion
        # Simulate motion detection with a 30% chance of detecting motion
        rand < 0.3
      end
    end

    # Light level sensor that can detect ambient light
    class LightSensor < Sensor
      attr_reader :location

      def initialize(name:, location:, **properties)
        @location = location
        super(name: name, **properties)
      end

      def perceive
        light_level = measure_light_level
        {
          light_level: light_level,  # Value between 0 and 100
          location: location,
          timestamp: Time.now
        }
      end

      private

      def validate!
        super
        raise ArgumentError, "Location cannot be empty" if location.nil? || location.empty?
      end

      # Simulated light level measurement
      # In a real application, this would connect to an actual device
      def measure_light_level
        # Time-of-day-based simulation (brighter during day, darker at night)
        hour = Time.now.hour
        if (6..18).cover?(hour)
          # Daytime: 50-100 light level
          rand(50..100)
        else
          # Nighttime: 0-30 light level
          rand(0..30)
        end
      end
    end
  end
end
