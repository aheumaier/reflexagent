require "rails_helper"

RSpec.describe UseCases::FindAlert do
  let(:alert_repository) { instance_double("StoragePort") }
  let(:use_case) { described_class.new(storage_port: alert_repository) }

  describe "#call" do
    let(:test_alert) { { id: "test-alert-id", name: "Test Alert" } }

    context "when the alert exists" do
      before do
        allow(alert_repository).to receive(:find_alert).with("test-alert-id").and_return(test_alert)
      end

      it "returns the alert with the given ID" do
        result = use_case.call("test-alert-id")
        expect(result).to eq(test_alert)
      end
    end

    context "when the alert does not exist" do
      before do
        allow(alert_repository).to receive(:find_alert).with("non-existent-id").and_return(nil)
      end

      it "raises an ArgumentError" do
        expect { use_case.call("non-existent-id") }.to raise_error(ArgumentError)
      end
    end
  end

  describe "factory method" do
    let(:test_alert) { { id: "test-alert-id", name: "Test Alert" } }

    before do
      allow(alert_repository).to receive(:find_alert).with("test-alert-id").and_return(test_alert)
      DependencyContainer.register(:alert_repository, alert_repository)
    end

    after do
      DependencyContainer.reset
    end

    it "creates the use case with dependencies injected" do
      factory_created = UseCaseFactory.create_find_alert
      result = factory_created.call("test-alert-id")
      expect(result).to eq(test_alert)
    end
  end
end
