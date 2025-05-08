# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::EventLookupStrategy, type: :unit do
  let(:logger) { instance_double(Logger, debug: nil, error: nil) }
  let(:strategy) { described_class.new(logger) }

  describe "#find_record" do
    it "raises NotImplementedError" do
      expect { strategy.find_record("123") }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Repositories::UuidLookupStrategy, type: :unit do
  let(:logger) { instance_double(Logger, debug: nil) }
  let(:strategy) { described_class.new(logger) }

  describe "#find_record" do
    let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }

    it "looks up by aggregate_id" do
      expect(DomainEvent).to receive(:find_by).with(aggregate_id: uuid)
      strategy.find_record(uuid)
    end

    it "returns the found record" do
      record = instance_double(DomainEvent)
      allow(DomainEvent).to receive(:find_by).with(aggregate_id: uuid).and_return(record)

      result = strategy.find_record(uuid)

      expect(result).to eq(record)
    end
  end
end

RSpec.describe Repositories::NumericIdLookupStrategy, type: :unit do
  let(:logger) { instance_double(Logger, debug: nil) }
  let(:strategy) { described_class.new(logger) }

  describe "#find_record" do
    it "looks up by numeric ID" do
      expect(DomainEvent).to receive(:find_by).with(id: 123)
      strategy.find_record("123")
    end

    it "returns the found record" do
      record = instance_double(DomainEvent)
      allow(DomainEvent).to receive(:find_by).with(id: 123).and_return(record)

      result = strategy.find_record("123")

      expect(result).to eq(record)
    end
  end
end

RSpec.describe Repositories::FallbackLookupStrategy, type: :unit do
  let(:logger) { instance_double(Logger, debug: nil) }
  let(:strategy) { described_class.new(logger) }

  describe "#find_record" do
    let(:id_str) { "some-non-uuid-id" }

    it "tries looking up by ID first" do
      expect(DomainEvent).to receive(:find_by).with(id: id_str).and_return(nil)
      expect(DomainEvent).to receive(:find_by).with(aggregate_id: id_str).and_return(nil)
      allow(DomainEvent).to receive(:all).and_return([])

      strategy.find_record(id_str)
    end

    it "tries looking up by aggregate_id second" do
      record = instance_double(DomainEvent)
      allow(DomainEvent).to receive(:find_by).with(id: id_str).and_return(nil)
      expect(DomainEvent).to receive(:find_by).with(aggregate_id: id_str).and_return(record)

      result = strategy.find_record(id_str)

      expect(result).to eq(record)
    end

    it "falls back to scanning all events" do
      event1 = instance_double(DomainEvent, id: "other-id")
      event2 = instance_double(DomainEvent, id: id_str)

      allow(DomainEvent).to receive(:find_by).with(id: id_str).and_return(nil)
      allow(DomainEvent).to receive(:find_by).with(aggregate_id: id_str).and_return(nil)
      allow(DomainEvent).to receive(:all).and_return([event1, event2])

      expect(strategy.find_record(id_str)).to eq(event2)
    end
  end
end

RSpec.describe Repositories::EventLookupStrategyFactory, type: :unit do
  let(:logger) { instance_double(Logger) }

  describe ".for_id" do
    context "with UUID format" do
      let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }

      it "returns UuidLookupStrategy" do
        strategy = described_class.for_id(uuid, logger)
        expect(strategy).to be_a(Repositories::UuidLookupStrategy)
      end
    end

    context "with numeric format" do
      it "returns NumericIdLookupStrategy" do
        strategy = described_class.for_id("123", logger)
        expect(strategy).to be_a(Repositories::NumericIdLookupStrategy)
      end
    end

    context "with other format" do
      it "returns FallbackLookupStrategy" do
        strategy = described_class.for_id("some-id", logger)
        expect(strategy).to be_a(Repositories::FallbackLookupStrategy)
      end
    end
  end
end
