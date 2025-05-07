require "rails_helper"

RSpec.describe UseCases::FindEvent do
  include_context "with all mock ports"

  let(:event) do
    Domain::EventFactory.create(
      id: "test-event-id",
      name: "server.cpu.usage",
      data: { value: 85.5, host: "web-01" },
      source: "monitoring-agent",
      timestamp: Time.current
    )
  end

  let(:use_case) { described_class.new(storage_port: mock_storage_port) }

  before do
    # Pre-save an event in the mock storage
    mock_storage_port.save_event(event)
  end

  describe "#call" do
    context "when the event exists" do
      it "returns the event with the given ID" do
        result = use_case.call("test-event-id")

        expect(result).to eq(event)
        expect(result.id).to eq("test-event-id")
        expect(result.name).to eq("server.cpu.usage")
      end
    end

    context "when the event does not exist" do
      it "raises an ArgumentError" do
        expect do
          use_case.call("non-existent-id")
        end.to raise_error(ArgumentError, "Event with ID 'non-existent-id' not found")
      end
    end
  end

  describe "factory method" do
    it "creates the use case with dependencies injected" do
      # Register our mock with the container
      DependencyContainer.register(:event_repository, mock_storage_port)

      # Create use case using factory
      factory_created = UseCaseFactory.create_find_event

      # Verify injected dependencies are working
      result = factory_created.call("test-event-id")

      expect(result).to eq(event)
      expect(result.id).to eq("test-event-id")
    end
  end
end
