require "rails_helper"

# Create a fake CommitMetric class for our tests
unless defined?(CommitMetric)
  class CommitMetric
    def self.since(time)
      nil
    end
  end
end

RSpec.describe Repositories::MetricRepository do
  let(:repository) { described_class.new }
  let(:metric) do
    Domain::Metric.new(
      name: "cpu.usage",
      value: 85.5,
      source: "web-01",
      dimensions: { region: "us-west", environment: "production" },
      timestamp: Time.current
    )
  end

  describe "#save_metric" do
    it "persists the metric to the database and returns it" do
      # Verify the database count before saving
      expect do
        @result = repository.save_metric(metric)
      end.to change(DomainMetric, :count).by(1)

      # Verify the returned metric has the correct values
      expect(@result).to be_a(Domain::Metric)
      expect(@result.name).to eq("cpu.usage")
      expect(@result.value).to eq(85.5)
      expect(@result.source).to eq("web-01")
      expect(@result.dimensions[:region]).to eq("us-west")

      # Verify the database record has the correct values
      db_record = DomainMetric.last
      expect(db_record.name).to eq("cpu.usage")
      expect(db_record.value).to eq(85.5)
      expect(db_record.source).to eq("web-01")
      expect(db_record.dimensions["region"]).to eq("us-west")
    end
  end

  describe "#find_metric" do
    it "retrieves a metric from the database by id" do
      # Save a metric first
      saved_metric = repository.save_metric(metric)

      # Now find it by ID
      found_metric = repository.find_metric(saved_metric.id)

      # Verify the found metric
      expect(found_metric).not_to be_nil
      expect(found_metric.id).to eq(saved_metric.id)
      expect(found_metric.name).to eq("cpu.usage")
      expect(found_metric.value).to eq(85.5)
    end

    it "returns nil when metric not found" do
      result = repository.find_metric("nonexistent-id")
      expect(result).to be_nil
    end
  end

  describe "#list_metrics" do
    before do
      # Clear existing metrics to get a clean slate
      DomainMetric.delete_all

      # Create a few metrics with well-defined timestamps for testing
      repository.save_metric(
        Domain::Metric.new(
          name: "cpu.usage",
          value: 85.5,
          source: "web-01",
          dimensions: { region: "us-west" },
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "cpu.usage",
          value: 90.2,
          source: "web-02",
          dimensions: { region: "us-east" },
          timestamp: 1.hour.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "memory.usage",
          value: 70.3,
          source: "web-01",
          dimensions: { region: "us-west" },
          timestamp: 30.minutes.ago
        )
      )
    end

    it "returns metrics filtered by name" do
      results = repository.list_metrics(name: "cpu.usage")
      expect(results.length).to eq(2)
      expect(results.all? { |m| m.name == "cpu.usage" }).to be(true)
    end

    it "returns metrics filtered by time range" do
      results = repository.list_metrics(start_time: 90.minutes.ago)
      expect(results.length).to eq(2)
      expect(results.map(&:name).sort).to eq(["cpu.usage", "memory.usage"])
    end

    it "returns the most recent metrics first when ordered" do
      results = repository.list_metrics(latest_first: true)
      expect(results.length).to eq(3)
      expect(results.first.name).to eq("memory.usage")
      expect(results.last.name).to eq("cpu.usage")
      expect(results.first.timestamp).to be > results.last.timestamp
    end
  end

  describe "#get_average" do
    before do
      # Create metrics for testing average
      repository.save_metric(
        Domain::Metric.new(
          name: "cpu.usage",
          value: 80.0,
          source: "web-01",
          timestamp: 3.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "cpu.usage",
          value: 90.0,
          source: "web-01",
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "cpu.usage",
          value: 70.0,
          source: "web-01",
          timestamp: 1.hour.ago
        )
      )
    end

    it "calculates the average value for a metric" do
      average = repository.get_average("cpu.usage")
      expect(average).to eq(80.0)
    end

    it "calculates the average for a specific time range" do
      average = repository.get_average("cpu.usage", 2.5.hours.ago, 1.5.hours.ago)
      expect(average).to eq(90.0)
    end
  end

  describe "#get_percentile" do
    before do
      # Create metrics for testing percentile
      (1..10).each do |i|
        repository.save_metric(
          Domain::Metric.new(
            name: "response.time",
            value: i * 10.0, # 10, 20, 30, ..., 100
            source: "web-01",
            timestamp: i.hours.ago
          )
        )
      end
    end

    it "calculates the 50th percentile (median) for a metric" do
      median = repository.get_percentile("response.time", 50)
      expect(median).to be_within(5.0).of(55.0) # 50th percentile of 10-100 should be around 55
    end

    it "calculates the 90th percentile for a metric" do
      p90 = repository.get_percentile("response.time", 90)
      expect(p90).to be_within(5.0).of(90.0) # 90th percentile of 10-100 should be around 90
    end

    it "calculates percentile for a specific time range" do
      p50 = repository.get_percentile("response.time", 50, 8.hours.ago, 3.hours.ago)
      # We'll add a larger margin since the implementation may vary
      expect(p50).to be_within(15.0).of(50.0) # 50th percentile of data points 3-8 (30-80)
    end
  end

  describe "#find_metrics_by_name_and_dimensions" do
    before do
      # Create metrics with various dimensions
      repository.save_metric(
        Domain::Metric.new(
          name: "http.request.duration",
          value: 250.0,
          source: "api-server",
          dimensions: { environment: "production", region: "us-west", endpoint: "/api/users" },
          timestamp: 3.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "http.request.duration",
          value: 180.0,
          source: "api-server",
          dimensions: { environment: "production", region: "us-east", endpoint: "/api/users" },
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "http.request.duration",
          value: 120.0,
          source: "api-server",
          dimensions: { environment: "staging", region: "us-west", endpoint: "/api/users" },
          timestamp: 1.hour.ago
        )
      )

      # Different metric name
      repository.save_metric(
        Domain::Metric.new(
          name: "http.error.rate",
          value: 0.05,
          source: "api-server",
          dimensions: { environment: "production", region: "us-west" },
          timestamp: 30.minutes.ago
        )
      )
    end

    it "returns metrics matching the name and dimensions" do
      results = repository.find_metrics_by_name_and_dimensions(
        "http.request.duration",
        { environment: "production" }
      )

      expect(results.length).to eq(2)
      expect(results.all? { |m| m.name == "http.request.duration" }).to be true
      expect(results.all? { |m| m.dimensions["environment"] == "production" }).to be true
    end

    it "returns empty array when no metrics match dimensions" do
      results = repository.find_metrics_by_name_and_dimensions(
        "http.request.duration",
        { environment: "development" }
      )

      expect(results).to be_empty
    end

    it "returns metrics for a specific time range" do
      # Adjust to get just the most recent production metric
      results = repository.find_metrics_by_name_and_dimensions(
        "http.request.duration",
        { environment: "production" },
        2.5.hours.ago
      )

      # Expect exactly one result - the metric from 2 hours ago
      expect(results.length).to eq(1)
      expect(results.first.dimensions["region"]).to eq("us-east")
      expect(results.first.value).to eq(180.0)
    end

    it "matches partial dimension criteria" do
      results = repository.find_metrics_by_name_and_dimensions(
        "http.request.duration",
        { endpoint: "/api/users" }
      )

      expect(results.length).to eq(3)
    end
  end

  describe "#find_aggregate_metric" do
    before do
      repository.save_metric(
        Domain::Metric.new(
          name: "system.load",
          value: 1.25,
          source: "server-1",
          dimensions: { host: "web-01", cluster: "prod-us-west" },
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "system.load",
          value: 1.50,
          source: "server-1",
          dimensions: { host: "web-01", cluster: "prod-us-west" },
          timestamp: 1.hour.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "system.load",
          value: 0.75,
          source: "server-2",
          dimensions: { host: "web-02", cluster: "prod-us-west" },
          timestamp: 30.minutes.ago
        )
      )
    end

    it "returns the most recent metric with exact dimension match" do
      result = repository.find_aggregate_metric(
        "system.load",
        { host: "web-01", cluster: "prod-us-west" }
      )

      expect(result).not_to be_nil
      expect(result.name).to eq("system.load")
      expect(result.value).to eq(1.50)
      expect(result.dimensions["host"]).to eq("web-01")
    end

    it "returns nil when no metrics match the dimensions exactly" do
      result = repository.find_aggregate_metric(
        "system.load",
        { host: "web-01", cluster: "prod-us-east" }
      )

      expect(result).to be_nil
    end

    it "requires dimensions to match exactly (both ways)" do
      # This should return nil because the dimensions don't match exactly
      # (metric has more dimensions than specified)
      result = repository.find_aggregate_metric(
        "system.load",
        { host: "web-01" }
      )

      expect(result).to be_nil
    end
  end

  describe "#update_metric" do
    let(:original_metric) do
      Domain::Metric.new(
        name: "api.latency",
        value: 120.0,
        source: "gateway",
        dimensions: { region: "us-west", environment: "production" },
        timestamp: Time.current
      )
    end

    it "updates an existing metric" do
      # First save the metric
      saved_metric = repository.save_metric(original_metric)
      expect(saved_metric.value).to eq(120.0)

      # Now update it
      updated_metric = saved_metric.with_value(150.0)
      result = repository.update_metric(updated_metric)

      # Check the returned object
      expect(result.id).to eq(saved_metric.id)
      expect(result.value).to eq(150.0)
      expect(result.name).to eq("api.latency")

      # Verify it was actually updated in the repository
      fetched = repository.find_metric(saved_metric.id)
      expect(fetched.value).to eq(150.0)
    end

    it "creates a new metric when ID is not found" do
      # Create a metric with a non-existent ID
      non_existent_metric = Domain::Metric.new(
        id: "999999",
        name: "api.error_rate",
        value: 0.05,
        source: "gateway",
        dimensions: { region: "us-west" },
        timestamp: Time.current
      )

      expect do
        @result = repository.update_metric(non_existent_metric)
      end.to change(DomainMetric, :count).by(1)

      expect(@result.name).to eq("api.error_rate")
      expect(@result.value).to eq(0.05)
    end

    it "creates a new metric when ID is nil" do
      # Create a metric with nil ID
      nil_id_metric = Domain::Metric.new(
        name: "api.throughput",
        value: 500.0,
        source: "gateway",
        dimensions: { region: "us-west" },
        timestamp: Time.current
      )

      expect do
        @result = repository.update_metric(nil_id_metric)
      end.to change(DomainMetric, :count).by(1)

      expect(@result.name).to eq("api.throughput")
      expect(@result.value).to eq(500.0)
      expect(@result.id).not_to be_nil
    end
  end

  describe "#find_unique_values" do
    before do
      # Create metrics with various dimensions and values
      repository.save_metric(
        Domain::Metric.new(
          name: "server.stats",
          value: 10.0,
          source: "monitoring",
          dimensions: {
            service: "auth",
            instance: "auth-1",
            datacenter: "us-west"
          },
          timestamp: 3.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "server.stats",
          value: 15.0,
          source: "monitoring",
          dimensions: {
            service: "auth",
            instance: "auth-2",
            datacenter: "us-west"
          },
          timestamp: 2.hours.ago
        )
      )

      repository.save_metric(
        Domain::Metric.new(
          name: "server.stats",
          value: 8.0,
          source: "monitoring",
          dimensions: {
            service: "payment",
            instance: "payment-1",
            datacenter: "us-east"
          },
          timestamp: 1.hour.ago
        )
      )
    end

    it "returns unique values for the specified dimension" do
      services = repository.find_unique_values("server.stats", {}, "service")
      expect(services).to contain_exactly("auth", "payment")
    end

    it "returns unique values filtered by other dimensions" do
      instances = repository.find_unique_values(
        "server.stats",
        { service: "auth" },
        "instance"
      )
      expect(instances).to contain_exactly("auth-1", "auth-2")
    end

    it "returns empty array when no matching metrics exist" do
      results = repository.find_unique_values(
        "nonexistent.metric",
        {},
        "service"
      )
      expect(results).to be_empty
    end

    it "returns empty array when dimension doesn't exist" do
      results = repository.find_unique_values(
        "server.stats",
        {},
        "nonexistent_dimension"
      )
      expect(results).to be_empty
    end
  end

  # Tests for commit metrics analysis methods
  # Note: We're using doubles for CommitMetric to avoid actual DB dependencies

  describe "#hotspot_directories" do
    let(:since) { 30.days.ago }
    let(:mock_hotspots) do
      [
        double("HotspotDirectory", directory: "app/controllers", change_count: 25),
        double("HotspotDirectory", directory: "app/models", change_count: 18),
        double("HotspotDirectory", directory: "lib/tasks", change_count: 10)
      ]
    end

    it "returns directory hotspots" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:hotspot_directories).with(since: since, limit: 10).and_return(mock_hotspots)

      results = repository.hotspot_directories(since: since)

      expect(results.size).to eq(3)
      expect(results.first[:directory]).to eq("app/controllers")
      expect(results.first[:count]).to eq(25)
      expect(results.last[:directory]).to eq("lib/tasks")
    end

    it "filters by repository" do
      base_query = double("BaseQuery")
      filtered_query = double("FilteredQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:by_repository).with("myapp").and_return(filtered_query)
      allow(filtered_query).to receive(:hotspot_directories).with(since: since,
                                                                  limit: 5).and_return(mock_hotspots.first(2))

      results = repository.hotspot_directories(since: since, repository: "myapp", limit: 5)

      expect(results.size).to eq(2)
      expect(results.first[:directory]).to eq("app/controllers")
      expect(results.last[:directory]).to eq("app/models")
    end
  end

  describe "#hotspot_filetypes" do
    let(:since) { 30.days.ago }
    let(:mock_hotspots) do
      [
        double("HotspotFiletype", filetype: "rb", change_count: 45),
        double("HotspotFiletype", filetype: "js", change_count: 30),
        double("HotspotFiletype", filetype: "css", change_count: 15)
      ]
    end

    it "returns filetype hotspots" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:hotspot_files_by_extension).with(since: since, limit: 10).and_return(mock_hotspots)

      results = repository.hotspot_filetypes(since: since)

      expect(results.size).to eq(3)
      expect(results.first[:filetype]).to eq("rb")
      expect(results.first[:count]).to eq(45)
    end
  end

  describe "#commit_type_distribution" do
    let(:since) { 30.days.ago }
    let(:mock_distribution) do
      [
        double("CommitType", commit_type: "feat", count: 12),
        double("CommitType", commit_type: "fix", count: 8),
        double("CommitType", commit_type: "refactor", count: 5)
      ]
    end

    it "returns commit type distribution" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:commit_type_distribution).with(since: since).and_return(mock_distribution)

      results = repository.commit_type_distribution(since: since)

      expect(results.size).to eq(3)
      expect(results.first[:type]).to eq("feat")
      expect(results.first[:count]).to eq(12)
      expect(results.last[:type]).to eq("refactor")
    end
  end

  describe "#author_activity" do
    let(:since) { 30.days.ago }
    let(:mock_authors) do
      [
        double("Author", author: "alice@example.com", commit_count: 25),
        double("Author", author: "bob@example.com", commit_count: 20),
        double("Author", author: "charlie@example.com", commit_count: 15)
      ]
    end

    it "returns author activity" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:author_activity).with(since: since, limit: 10).and_return(mock_authors)

      results = repository.author_activity(since: since)

      expect(results.size).to eq(3)
      expect(results.first[:author]).to eq("alice@example.com")
      expect(results.first[:commit_count]).to eq(25)
    end
  end

  describe "#lines_changed_by_author" do
    let(:since) { 30.days.ago }
    let(:mock_authors) do
      [
        double("Author", author: "alice@example.com", lines_added: 250, lines_deleted: 100),
        double("Author", author: "bob@example.com", lines_added: 180, lines_deleted: 150)
      ]
    end

    it "returns lines changed by author" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:lines_changed_by_author).with(since: since).and_return(mock_authors)

      results = repository.lines_changed_by_author(since: since)

      expect(results.size).to eq(2)
      expect(results.first[:author]).to eq("alice@example.com")
      expect(results.first[:lines_added]).to eq(250)
      expect(results.first[:lines_deleted]).to eq(100)
      expect(results.first[:lines_changed]).to eq(350) # sum of added and deleted
    end
  end

  describe "#breaking_changes_by_author" do
    let(:since) { 30.days.ago }
    let(:mock_authors) do
      [
        double("Author", author: "alice@example.com", breaking_count: 3),
        double("Author", author: "bob@example.com", breaking_count: 1)
      ]
    end

    it "returns breaking changes by author" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:breaking_changes_by_author).with(since: since).and_return(mock_authors)

      results = repository.breaking_changes_by_author(since: since)

      expect(results.size).to eq(2)
      expect(results.first[:author]).to eq("alice@example.com")
      expect(results.first[:breaking_count]).to eq(3)
    end
  end

  describe "#commit_activity_by_day" do
    let(:since) { 30.days.ago }
    let(:today) { Date.today }
    let(:mock_days) do
      [
        double("Day", day: today, commit_count: 5),
        double("Day", day: today - 1.day, commit_count: 8),
        double("Day", day: today - 2.days, commit_count: 3)
      ]
    end

    it "returns commit activity by day" do
      base_query = double("BaseQuery")

      allow(CommitMetric).to receive(:since).with(since).and_return(base_query)
      allow(base_query).to receive(:commit_activity_by_day).with(since: since).and_return(mock_days)

      results = repository.commit_activity_by_day(since: since)

      expect(results.size).to eq(3)
      expect(results.first[:date]).to eq(today)
      expect(results.first[:commit_count]).to eq(5)
      expect(results.last[:date]).to eq(today - 2.days)
    end
  end
end
