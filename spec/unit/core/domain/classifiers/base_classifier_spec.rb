# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::BaseClassifier do
  let(:dimension_extractor) { instance_double("Domain::Extractors::DimensionExtractor") }
  let(:classifier) { described_class.new(dimension_extractor) }
  let(:event) { FactoryBot.build(:event) }

  describe "#initialize" do
    it "accepts a dimension extractor" do
      expect(classifier.dimension_extractor).to eq(dimension_extractor)
    end

    it "works without a dimension extractor" do
      classifier = described_class.new
      expect(classifier.dimension_extractor).to be_nil
    end
  end

  describe "#classify" do
    it "raises NotImplementedError" do
      expect do
        classifier.classify(event)
      end.to raise_error(NotImplementedError, "Subclasses must implement classify method")
    end
  end

  describe "#create_metric" do
    it "creates a metric definition with the given parameters" do
      metric = classifier.create_metric(name: "test.metric", value: 42, dimensions: { foo: "bar" })

      expect(metric).to be_a(Hash)
      expect(metric[:name]).to eq("test.metric")
      expect(metric[:value]).to eq(42)
      expect(metric[:dimensions]).to eq({ foo: "bar" })
    end

    it "creates a metric with empty dimensions by default" do
      metric = classifier.create_metric(name: "test.metric", value: 42)

      expect(metric[:dimensions]).to eq({})
    end
  end

  describe "#extract_event_parts" do
    context "with a composite event name" do
      let(:event) { FactoryBot.build(:event, name: "github.pull_request.opened") }

      it "extracts the event type and action correctly" do
        event_type, action = classifier.extract_event_parts(event, "github")

        expect(event_type).to eq("pull_request")
        expect(action).to eq("opened")
      end
    end

    context "with a simple event name" do
      let(:event) { FactoryBot.build(:event, name: "github.push") }

      it "extracts the event type and returns nil for action" do
        event_type, action = classifier.extract_event_parts(event, "github")

        expect(event_type).to eq("push")
        expect(action).to be_nil
      end
    end
  end

  # Example implementation of a subclass for testing purposes
  class TestClassifier < Domain::Classifiers::BaseClassifier
    def classify(event)
      { metrics: [create_metric(name: "test.metric", value: 1)] }
    end
  end

  describe "subclass implementation" do
    let(:test_classifier) { TestClassifier.new }

    it "can be subclassed and implement classify" do
      result = test_classifier.classify(event)

      expect(result).to be_a(Hash)
      expect(result[:metrics]).to be_an(Array)
      expect(result[:metrics].first[:name]).to eq("test.metric")
    end
  end
end
