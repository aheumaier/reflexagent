# frozen_string_literal: true

require "rails_helper"

RSpec.describe RawEventJob, :problematic do
  describe "#perform" do
    let(:payload_wrapper) do
      {
        id: "test-123",
        source: "github",
        payload: '{"action":"opened","issue":{"number":1}}',
        received_at: Time.current.iso8601,
        status: "pending"
      }
    end

    let(:process_event_use_case) { instance_double("ProcessEvent") }

    before do
      allow(UseCaseFactory).to receive(:create_process_event).and_return(process_event_use_case)
      allow(process_event_use_case).to receive(:call)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:debug)
    end

    it "processes the event with the process_event use case" do
      expect(process_event_use_case).to receive(:call).with(
        payload_wrapper[:payload],
        source: payload_wrapper[:source]
      )

      subject.perform(payload_wrapper)
    end

    it "logs success after processing" do
      expect(Rails.logger).to receive(:info).with(/Processed raw event/)

      subject.perform(payload_wrapper)
    end

    context "when the payload has string keys" do
      let(:string_keyed_payload) do
        {
          "id" => "test-123",
          "source" => "github",
          "payload" => '{"action":"opened","issue":{"number":1}}',
          "received_at" => Time.current.iso8601,
          "status" => "pending"
        }
      end

      it "converts string keys to symbols" do
        expect(process_event_use_case).to receive(:call).with(
          string_keyed_payload["payload"],
          source: string_keyed_payload["source"]
        )

        subject.perform(string_keyed_payload)
      end
    end

    context "when an error occurs" do
      let(:error_message) { "Test error" }
      let(:test_error) { StandardError.new(error_message) }

      before do
        allow(process_event_use_case).to receive(:call).and_raise(test_error)
      end

      it "logs the error" do
        # Match the exact format from the implementation
        expect(Rails.logger).to receive(:error).with("Error processing raw event test-123: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        expect { subject.perform(payload_wrapper) }.to raise_error(StandardError)
      end

      it "reraises the error for Sidekiq to handle retries" do
        expect { subject.perform(payload_wrapper) }.to raise_error(StandardError, "Test error")
      end
    end
  end
end
