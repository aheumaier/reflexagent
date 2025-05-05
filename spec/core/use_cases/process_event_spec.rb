require "rails_helper"

RSpec.describe Core::UseCases::ProcessEvent do
  let(:ingestion_port) { instance_double(Ports::IngestionPort) }
  let(:storage_port) { instance_double(Ports::StoragePort) }
  let(:queue_port) { instance_double(Ports::QueuePort) }

  let(:use_case) do
    described_class.new(ingestion_port: ingestion_port, storage_port: storage_port, queue_port: queue_port)
  end

  let(:raw_payload) { { key: "value" }.to_json }
  let(:source) { "github" }
  let(:event) { instance_double(Domain::Event, id: "event-123", name: "github.push", source: "github") }

  describe "#call" do
    before do
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:error)

      # Default behavior for successful path
      allow(ingestion_port).to receive(:receive_event).with(raw_payload, source: source).and_return(event)
      allow(storage_port).to receive(:save_event).with(event).and_return(true)
      allow(queue_port).to receive(:enqueue_metric_calculation).with(event).and_return(true)
    end

    it "parses the raw payload into a domain event" do
      expect(ingestion_port).to receive(:receive_event).with(raw_payload, source: source).and_return(event)

      use_case.call(raw_payload, source: source)
    end

    it "stores the event" do
      expect(storage_port).to receive(:save_event).with(event)

      use_case.call(raw_payload, source: source)
    end

    it "enqueues the event for metric calculation" do
      expect(queue_port).to receive(:enqueue_metric_calculation).with(event)

      use_case.call(raw_payload, source: source)
    end

    it "returns the processed event" do
      result = use_case.call(raw_payload, source: source)

      expect(result).to eq(event)
    end

    context "when event parsing fails" do
      before do
        allow(ingestion_port).to receive(:receive_event).and_raise("Parsing error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Error parsing event/)

        expect do
          use_case.call(raw_payload, source: source)
        end.to raise_error(Core::UseCases::ProcessEvent::EventParsingError)
      end

      it "raises an EventParsingError" do
        expect do
          use_case.call(raw_payload, source: source)
        end.to raise_error(Core::UseCases::ProcessEvent::EventParsingError, /Failed to parse event/)
      end
    end

    context "when event storage fails" do
      before do
        allow(storage_port).to receive(:save_event).and_raise("Storage error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Error saving event/)

        expect do
          use_case.call(raw_payload, source: source)
        end.to raise_error(Core::UseCases::ProcessEvent::EventStorageError)
      end

      it "raises an EventStorageError" do
        expect do
          use_case.call(raw_payload, source: source)
        end.to raise_error(Core::UseCases::ProcessEvent::EventStorageError, /Failed to save event/)
      end
    end

    context "when metric calculation enqueuing fails" do
      before do
        allow(queue_port).to receive(:enqueue_metric_calculation).and_raise("Queue error")
      end

      it "logs the error but continues processing" do
        expect(Rails.logger).to receive(:error).with(/Error enqueuing event/)
        expect(Rails.logger).to receive(:error).with(/Continuing despite enqueueing error/)

        # The use case should NOT raise an error in this case
        expect do
          use_case.call(raw_payload, source: source)
        end.not_to raise_error
      end

      it "still returns the event" do
        result = use_case.call(raw_payload, source: source)

        expect(result).to eq(event)
      end
    end
  end
end
