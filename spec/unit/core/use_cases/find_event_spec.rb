require "rails_helper"

RSpec.describe UseCases::FindEvent do
  let(:event_repository) { instance_double("StoragePort") }
  let(:use_case) { described_class.new(storage_port: event_repository) }

  describe "#call" do
    let(:test_event) { { id: "test-event-id", name: "Test Event" } }

    context "when the event exists" do
      before do
        allow(event_repository).to receive(:find_event).with("test-event-id").and_return(test_event)
      end

      it "returns the event with the given ID" do
        result = use_case.call("test-event-id")
        expect(result).to eq(test_event)
      end
    end

    context "when the event does not exist" do
      before do
        allow(event_repository).to receive(:find_event).with("non-existent-id").and_return(nil)
      end

      it "raises an ArgumentError" do
        expect { use_case.call("non-existent-id") }.to raise_error(ArgumentError)
      end
    end
  end

  describe "factory method" do
    let(:test_event) { { id: "test-event-id", name: "Test Event" } }

    before do
      allow(event_repository).to receive(:find_event).with("test-event-id").and_return(test_event)
      DependencyContainer.register(:event_repository, event_repository)
    end

    after do
      DependencyContainer.reset
    end

    it "creates the use case with dependencies injected" do
      factory_created = UseCaseFactory.create_find_event
      result = factory_created.call("test-event-id")
      expect(result).to eq(test_event)
    end
  end
end
