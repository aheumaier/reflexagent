# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::MetricRepositoryFactory do
  let(:metric_naming_port) { double("MetricNamingPort") }
  let(:logger_port) { double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:factory) { described_class.new(metric_naming_port: metric_naming_port, logger_port: logger_port) }

  describe "#initialize" do
    it "initializes with provided dependencies" do
      expect(factory.instance_variable_get(:@metric_naming_port)).to eq(metric_naming_port)
      expect(factory.instance_variable_get(:@logger_port)).to eq(logger_port)
      expect(factory.instance_variable_get(:@repository_cache)).to eq({})
    end

    it "uses defaults when dependencies are not provided" do
      # Stub the Rails.logger to avoid test dependency on Rails
      allow(Rails).to receive(:logger).and_return(double("Rails.logger"))

      # Assume Adapters::Metrics::MetricNamingAdapter exists but don't instantiate it
      metric_naming_adapter = double("MetricNamingAdapter")
      allow(Adapters::Metrics::MetricNamingAdapter).to receive(:new).and_return(metric_naming_adapter)

      factory_with_defaults = described_class.new

      expect(factory_with_defaults.instance_variable_get(:@logger_port)).to eq(Rails.logger)
      expect(factory_with_defaults.instance_variable_get(:@repository_cache)).to eq({})
    end
  end

  describe "repository getters" do
    before do
      # Mock the repository classes
      allow(Repositories::BaseMetricRepository).to receive(:new).and_return(double("BaseMetricRepository"))
      allow(Repositories::GitMetricRepository).to receive(:new).and_return(double("GitMetricRepository"))
      allow(Repositories::DoraMetricsRepository).to receive(:new).and_return(double("DoraMetricsRepository"))
      allow(Repositories::IssueMetricRepository).to receive(:new).and_return(double("IssueMetricRepository"))
      allow(Repositories::MetricRepository).to receive(:new).and_return(double("MetricRepository"))
    end

    it "returns a BaseMetricRepository instance" do
      expect(factory.base_repository).to be_a(RSpec::Mocks::Double)
      expect(Repositories::BaseMetricRepository).to have_received(:new).with(
        metric_naming_port: metric_naming_port,
        logger_port: logger_port
      )
    end

    it "returns a GitMetricRepository instance" do
      expect(factory.git_repository).to be_a(RSpec::Mocks::Double)
      expect(Repositories::GitMetricRepository).to have_received(:new).with(
        metric_naming_port: metric_naming_port,
        logger_port: logger_port
      )
    end

    it "returns a DoraMetricsRepository instance" do
      expect(factory.dora_repository).to be_a(RSpec::Mocks::Double)
      expect(Repositories::DoraMetricsRepository).to have_received(:new).with(
        metric_naming_port: metric_naming_port,
        logger_port: logger_port
      )
    end

    it "returns an IssueMetricRepository instance" do
      expect(factory.issue_repository).to be_a(RSpec::Mocks::Double)
      expect(Repositories::IssueMetricRepository).to have_received(:new).with(
        metric_naming_port: metric_naming_port,
        logger_port: logger_port
      )
    end

    it "returns a legacy MetricRepository instance" do
      expect(factory.legacy_repository).to be_a(RSpec::Mocks::Double)
      expect(Repositories::MetricRepository).to have_received(:new).with(
        logger_port: logger_port
      )
    end

    it "returns a repository by name" do
      expect(factory.repository(:base)).to be_a(RSpec::Mocks::Double)
      expect(factory.repository(:git)).to be_a(RSpec::Mocks::Double)
      expect(factory.repository(:dora)).to be_a(RSpec::Mocks::Double)
      expect(factory.repository(:issue)).to be_a(RSpec::Mocks::Double)
      expect(factory.repository(:legacy)).to be_a(RSpec::Mocks::Double)
    end

    it "raises an error for unknown repository types" do
      expect { factory.repository(:unknown) }.to raise_error(ArgumentError, "Unknown repository type: unknown")
    end
  end

  describe "#clear_cache" do
    it "clears the repository cache" do
      # Create some repositories to populate the cache
      factory.base_repository
      factory.git_repository

      # Verify cache is populated
      expect(factory.instance_variable_get(:@repository_cache).size).to eq(2)

      # Clear the cache
      factory.clear_cache

      # Verify cache is empty
      expect(factory.instance_variable_get(:@repository_cache)).to eq({})
    end
  end

  describe "caching behavior" do
    it "caches repository instances" do
      # Mock the BaseMetricRepository class
      allow(Repositories::BaseMetricRepository).to receive(:new).and_return(double("BaseMetricRepository"))

      # Get the repository twice
      repo1 = factory.base_repository
      repo2 = factory.base_repository

      # Verify that new was only called once
      expect(Repositories::BaseMetricRepository).to have_received(:new).exactly(1).time

      # Verify that the same instance was returned
      expect(repo1).to be(repo2)
    end

    it "creates new instances after clearing the cache" do
      # Mock the BaseMetricRepository class
      allow(Repositories::BaseMetricRepository).to receive(:new).and_return(double("BaseMetricRepository"),
                                                                            double("BaseMetricRepository2"))

      # Get the repository
      repo1 = factory.base_repository

      # Clear the cache
      factory.clear_cache

      # Get the repository again
      repo2 = factory.base_repository

      # Verify that new was called twice
      expect(Repositories::BaseMetricRepository).to have_received(:new).exactly(2).times

      # Verify that different instances were returned
      expect(repo1).not_to be(repo2)
    end
  end
end
