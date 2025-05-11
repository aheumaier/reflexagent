# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::BaseMetricRepository do
  let(:metric_naming_port) { double("MetricNamingPort") }
  let(:logger_port) { double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(metric_naming_port: metric_naming_port, logger_port: logger_port) }

  let(:test_metric) do
    Domain::Metric.new(
      name: "test.metric.total",
      value: 42.0,
      source: "test-source",
      dimensions: { "key" => "value" },
      timestamp: Time.current
    )
  end

  let(:domain_metric_record) do
    instance_double(
      "DomainMetric",
      id: 123,
      name: "test.metric.total",
      value: 42.0,
      source: "test-source",
      dimensions: { "key" => "value" },
      recorded_at: Time.current
    )
  end

  describe "#save_metric" do
    it "saves a metric to the database and return the saved object" do
      # Arrange
      allow(DomainMetric).to receive(:create!).and_return(domain_metric_record)

      # Act
      result = repository.save_metric(test_metric)

      # Assert
      expect(DomainMetric).to have_received(:create!).with(
        name: test_metric.name,
        value: test_metric.value,
        source: test_metric.source,
        dimensions: test_metric.dimensions,
        recorded_at: test_metric.timestamp
      )
      expect(result).to be_a(Domain::Metric)
      expect(result.id).to eq("123")
    end

    it "assigns an ID to the metric if it doesn't have one" do
      # Arrange
      allow(DomainMetric).to receive(:create!).and_return(domain_metric_record)

      # Act
      result = repository.save_metric(test_metric)

      # Assert
      expect(result.id).to eq("123")
    end

    it "stores the metric in the cache" do
      # Arrange
      allow(DomainMetric).to receive(:create!).and_return(domain_metric_record)

      # Act
      repository.save_metric(test_metric)

      # Get the metric from cache
      repository.instance_variable_get(:@metrics_cache)["123"]

      # Assert - use the instance variable to check the cache
      cached_metric = repository.instance_variable_get(:@metrics_cache)["123"]
      expect(cached_metric).to be_a(Domain::Metric)
      expect(cached_metric.id).to eq("123")
    end
  end

  describe "#find_metric" do
    before do
      allow(DomainMetric).to receive(:find_latest_by_id).and_return(nil)
    end

    it "retrieves a metric from cache if available" do
      # Arrange
      # Add the metric to the cache
      repository.instance_variable_set(:@metrics_cache, { "123" => test_metric.with_id("123") })

      # Act
      result = repository.find_metric("123")

      # Assert
      expect(result).to eq(test_metric.with_id("123"))
      # Ensure no database queries happened
      expect(DomainMetric).not_to have_received(:find_latest_by_id)
    end

    it "retrieves a metric from the database if not in cache" do
      # Arrange
      allow(DomainMetric).to receive(:find_latest_by_id).with(123).and_return(domain_metric_record)

      # Act
      result = repository.find_metric(123)

      # Assert
      expect(DomainMetric).to have_received(:find_latest_by_id).with(123)
      expect(result).to be_a(Domain::Metric)
      expect(result.id).to eq("123")
    end

    it "returns nil if the metric is not found" do
      # Arrange
      allow(DomainMetric).to receive(:find_latest_by_id).with(999).and_return(nil)

      # Act
      result = repository.find_metric(999)

      # Assert
      expect(result).to be_nil
    end
  end

  describe "#update_metric" do
    let(:metric_with_id) { test_metric.with_id("123") }

    it "updates an existing metric in the database" do
      # Arrange
      allow(DomainMetric).to receive(:find_by_id_only).with(123).and_return(domain_metric_record)
      allow(domain_metric_record).to receive(:update!).and_return(true)

      # Act
      result = repository.update_metric(metric_with_id)

      # Assert
      expect(domain_metric_record).to have_received(:update!).with(
        name: metric_with_id.name,
        value: metric_with_id.value,
        source: metric_with_id.source,
        dimensions: metric_with_id.dimensions,
        recorded_at: metric_with_id.timestamp
      )
      expect(result).to eq(metric_with_id)
    end

    it "saves a new metric if ID not found" do
      # Arrange
      allow(DomainMetric).to receive(:find_by_id_only).with(123).and_return(nil)
      allow(DomainMetric).to receive(:create!).and_return(domain_metric_record)

      # Act
      result = repository.update_metric(metric_with_id)

      # Assert
      expect(DomainMetric).to have_received(:create!)
      expect(result).to be_a(Domain::Metric)
    end

    it "updates the cache" do
      # Arrange
      allow(DomainMetric).to receive(:find_by_id_only).with(123).and_return(domain_metric_record)
      allow(domain_metric_record).to receive(:update!).and_return(true)

      # Act
      repository.update_metric(metric_with_id)

      # Assert - use the instance variable to check the cache
      cached_metric = repository.instance_variable_get(:@metrics_cache)["123"]
      expect(cached_metric).to eq(metric_with_id)
    end
  end

  describe "#list_metrics" do
    let(:metrics_relation) { double("ActiveRecord::Relation") }
    let(:metric_record_1) do
      instance_double("DomainMetric", id: 1, name: "test.metric.total", value: 10.0, source: "test-source", dimensions: {},
                                      recorded_at: 1.day.ago)
    end
    let(:metric_record_2) do
      instance_double("DomainMetric", id: 2, name: "test.metric.total", value: 20.0, source: "test-source", dimensions: {},
                                      recorded_at: 2.days.ago)
    end

    before do
      allow(DomainMetric).to receive(:list_metrics).and_return([metric_record_1, metric_record_2])
    end

    it "applies name filter if provided" do
      # Act
      repository.list_metrics(name: "test.metric.total")

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(name: "test.metric.total")
      )
    end

    it "applies source filter if provided" do
      # Act
      repository.list_metrics(source: "test-source")

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(source: "test-source")
      )
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current

      # Act
      repository.list_metrics(start_time: start_time, end_time: end_time)

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(start_time: start_time, end_time: end_time)
      )
    end

    it "applies dimension filters if provided" do
      # Arrange
      dimensions = { "key" => "value" }

      # Act
      repository.list_metrics(dimensions: dimensions)

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(dimensions: dimensions)
      )
    end

    it "sorts by timestamp if requested" do
      # Act
      repository.list_metrics(latest_first: true)

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(latest_first: true)
      )
    end

    it "limits results if requested" do
      # Act
      repository.list_metrics(limit: 10)

      # Assert
      expect(DomainMetric).to have_received(:list_metrics).with(
        hash_including(limit: 10)
      )
    end
  end

  describe "#find_by_pattern" do
    let(:domain_metrics) { [domain_metric_record] }
    let(:query) { double("ActiveRecord::Relation") }

    before do
      allow(DomainMetric).to receive(:all).and_return(query)
      allow(query).to receive(:where).and_return(query)
      allow(query).to receive(:order).and_return(domain_metrics)
    end

    it "builds a query based on metric name components" do
      # Act
      result = repository.find_by_pattern(source: "test", entity: "metric", action: "total")

      # Assert
      expect(query).to have_received(:where).with(name: "test.metric.total")
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Domain::Metric)
    end

    it "applies source filter if provided" do
      # Act
      repository.find_by_pattern(source: "test")

      # Assert
      expect(query).to have_received(:where).with("name LIKE ?", "test.%")
    end

    it "applies entity filter if provided with other filters" do
      # Act
      repository.find_by_pattern(source: "test", entity: "metric", action: "total")

      # Assert
      expect(query).to have_received(:where).with(name: "test.metric.total")
    end

    it "applies action filter if provided with other filters" do
      # Act
      repository.find_by_pattern(source: "test", entity: "metric", action: "total")

      # Assert
      expect(query).to have_received(:where).with(name: "test.metric.total")
    end

    it "applies detail filter if provided" do
      # Act
      repository.find_by_pattern(source: "test", entity: "metric", action: "total", detail: "daily")

      # Assert
      expect(query).to have_received(:where).with(name: "test.metric.total.daily")
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current

      # Act
      repository.find_by_pattern(source: "test", start_time: start_time, end_time: end_time)

      # Assert
      expect(query).to have_received(:where).with("recorded_at >= ?", start_time)
      expect(query).to have_received(:where).with("recorded_at <= ?", end_time)
    end

    it "applies dimension filters if provided" do
      # Arrange
      dimensions = { "key" => "value" }

      # Act
      repository.find_by_pattern(source: "test", dimensions: dimensions)

      # Assert
      expect(query).to have_received(:where).with("dimensions @> ?", dimensions.to_json)
    end
  end

  describe "#find_by_source" do
    let(:domain_metrics) { [domain_metric_record] }
    let(:query) { double("ActiveRecord::Relation") }

    before do
      allow(DomainMetric).to receive(:where).and_return(query)
      allow(query).to receive(:where).and_return(query)
      allow(query).to receive(:order).and_return(domain_metrics)
    end

    it "finds all metrics for a specific source" do
      # Act
      result = repository.find_by_source("test-source")

      # Assert
      expect(DomainMetric).to have_received(:where).with("name LIKE ?", "test-source.%")
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Domain::Metric)
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current

      # Act
      repository.find_by_source("test-source", start_time: start_time, end_time: end_time)

      # Assert
      expect(query).to have_received(:where).with("recorded_at >= ?", start_time)
      expect(query).to have_received(:where).with("recorded_at <= ?", end_time)
    end
  end

  describe "#find_by_entity" do
    let(:domain_metrics) { [domain_metric_record] }
    let(:query) { double("ActiveRecord::Relation") }

    before do
      allow(DomainMetric).to receive(:where).and_return(query)
      allow(query).to receive(:where).and_return(query)
      allow(query).to receive(:order).and_return(domain_metrics)
    end

    it "finds all metrics for a specific entity" do
      # Act
      result = repository.find_by_entity("metric")

      # Assert
      expect(DomainMetric).to have_received(:where).with("name ~ ?", "^[^.]+\\.metric\\.")
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Domain::Metric)
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current

      # Act
      repository.find_by_entity("metric", start_time: start_time, end_time: end_time)

      # Assert
      expect(query).to have_received(:where).with("recorded_at >= ?", start_time)
      expect(query).to have_received(:where).with("recorded_at <= ?", end_time)
    end
  end

  describe "#find_by_action" do
    let(:domain_metrics) { [domain_metric_record] }
    let(:query) { double("ActiveRecord::Relation") }

    before do
      allow(DomainMetric).to receive(:where).and_return(query)
      allow(query).to receive(:where).and_return(query)
      allow(query).to receive(:order).and_return(domain_metrics)
    end

    it "finds all metrics for a specific action" do
      # Act
      result = repository.find_by_action("total")

      # Assert
      expect(DomainMetric).to have_received(:where).with("name ~ ?", "^[^.]+\\.[^.]+\\.total(\\.|$)")
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Domain::Metric)
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current

      # Act
      repository.find_by_action("total", start_time: start_time, end_time: end_time)

      # Assert
      expect(query).to have_received(:where).with("recorded_at >= ?", start_time)
      expect(query).to have_received(:where).with("recorded_at <= ?", end_time)
    end
  end

  describe "#get_average" do
    it "calculates the average value for metrics with a given name" do
      # Arrange
      allow(DomainMetric).to receive(:average_for).and_return(42.0)

      # Act
      result = repository.get_average("test.metric.total")

      # Assert
      expect(DomainMetric).to have_received(:average_for).with("test.metric.total", nil, nil)
      expect(result).to eq(42.0)
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current
      allow(DomainMetric).to receive(:average_for).and_return(42.0)

      # Act
      repository.get_average("test.metric.total", start_time, end_time)

      # Assert
      expect(DomainMetric).to have_received(:average_for).with("test.metric.total", start_time, end_time)
    end
  end

  describe "#get_percentile" do
    it "calculates the percentile value for metrics with a given name" do
      # Arrange
      allow(DomainMetric).to receive(:percentile_for).and_return(42.0)

      # Act
      result = repository.get_percentile("test.metric.total", 90)

      # Assert
      expect(DomainMetric).to have_received(:percentile_for).with("test.metric.total", 90, nil, nil)
      expect(result).to eq(42.0)
    end

    it "applies time range filters if provided" do
      # Arrange
      start_time = 1.week.ago
      end_time = Time.current
      allow(DomainMetric).to receive(:percentile_for).and_return(42.0)

      # Act
      repository.get_percentile("test.metric.total", 90, start_time, end_time)

      # Assert
      expect(DomainMetric).to have_received(:percentile_for).with("test.metric.total", 90, start_time, end_time)
    end
  end

  describe "#find_unique_values" do
    let(:metrics) do
      [
        Domain::Metric.new(
          name: "test.metric.total",
          value: 10.0,
          source: "test-source",
          dimensions: { "region" => "us-east" },
          timestamp: Time.current
        ),
        Domain::Metric.new(
          name: "test.metric.total",
          value: 20.0,
          source: "test-source",
          dimensions: { "region" => "us-west" },
          timestamp: Time.current
        ),
        Domain::Metric.new(
          name: "test.metric.total",
          value: 30.0,
          source: "test-source",
          dimensions: { "region" => "us-east" },
          timestamp: Time.current
        )
      ]
    end

    it "finds unique values for a dimension across matching metrics" do
      # Arrange
      allow(repository).to receive(:find_metrics_by_name_and_dimensions).and_return(metrics)

      # Act
      result = repository.find_unique_values("test.metric.total", {}, "region")

      # Assert
      expect(repository).to have_received(:find_metrics_by_name_and_dimensions).with("test.metric.total", {})
      expect(result).to contain_exactly("us-east", "us-west")
    end
  end

  describe "#to_domain_metric" do
    it "converts a database record to a domain model" do
      # Act
      result = repository.send(:to_domain_metric, domain_metric_record)

      # Assert
      expect(result).to be_a(Domain::Metric)
      expect(result.id).to eq("123")
      expect(result.name).to eq("test.metric.total")
      expect(result.value).to eq(42.0)
      expect(result.source).to eq("test-source")
      expect(result.dimensions).to eq({ "key" => "value" })
      expect(result.timestamp).to eq(domain_metric_record.recorded_at)
    end
  end
end
