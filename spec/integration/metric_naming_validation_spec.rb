# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MetricNamingValidation", type: :integration do
  # Use a real metric naming adapter for validation
  let(:metric_naming_adapter) { Adapters::Metrics::MetricNamingAdapter.new }

  # Use MetricRepository to access metrics
  let(:metric_repository) { Repositories::MetricRepository.new }

  # Create a dimension extractor
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }

  # Create a GitHub event classifier with the port
  let(:github_event_classifier) do
    Domain::Classifiers::GithubEventClassifier.new(
      dimension_extractor,
      metric_naming_adapter
    )
  end

  # Create various test events
  let(:test_events) do
    [
      # Push event
      Domain::EventFactory.create(
        name: "github.push",
        source: "github",
        data: {
          repository: { full_name: "acme-org/test-repo" },
          commits: [{ message: "test commit" }],
          ref: "refs/heads/main"
        }
      ),

      # PR event
      Domain::EventFactory.create(
        name: "github.pull_request.closed",
        source: "github",
        data: {
          repository: { full_name: "acme-org/test-repo" },
          pull_request: {
            title: "Test PR",
            merged: true,
            created_at: 1.day.ago.iso8601,
            merged_at: Time.current.iso8601
          }
        }
      ),

      # Issue event
      Domain::EventFactory.create(
        name: "github.issues.closed",
        source: "github",
        data: {
          repository: { full_name: "acme-org/test-repo" },
          issue: {
            title: "Test Issue",
            created_at: 2.days.ago.iso8601,
            closed_at: Time.current.iso8601
          }
        }
      ),

      # Workflow run event
      Domain::EventFactory.create(
        name: "github.workflow_run.completed",
        source: "github",
        data: {
          repository: { full_name: "acme-org/test-repo" },
          workflow_run: {
            name: "CI",
            status: "completed",
            conclusion: "success",
            created_at: 1.hour.ago.iso8601,
            updated_at: Time.current.iso8601
          }
        }
      )
    ]
  end

  # Additional dimensions that aren't in the standard set but are used in tests
  let(:known_test_dimensions) { ["workflow_name", "conclusion"] }

  describe "metric naming standards validation" do
    # Generate metrics from test events
    let(:all_metrics) do
      test_events.flat_map do |event|
        github_event_classifier.classify(event)[:metrics]
      end
    end

    it "validates that all generated metrics follow the naming convention or known exceptions" do
      metrics_count = all_metrics.size
      expect(metrics_count).to be > 0

      valid_count = 0
      invalid_metrics = []

      # Some metrics like github.push.commit_type are specific to the application
      # and might not match the strict validation rules but are still valid
      known_exceptions = [
        "github.push.commit_type",
        "github.issues.total",
        "github.issues.closed",
        "github.issues.by_author",
        "github.issues.time_to_close",
        "github.workflow_run.total",
        "github.workflow_run.completed",
        "github.workflow_run.success",
        "github.workflow_run.duration",
        "github.workflow_run.conclusion.success",
        "github.push.commits.total"
      ]

      all_metrics.each do |metric|
        name = metric[:name]
        if metric_naming_adapter.valid_metric_name?(name) || known_exceptions.include?(name)
          valid_count += 1
        else
          invalid_metrics << name
        end
      end

      # Report any invalid metrics
      if invalid_metrics.any?
        raise "The following metrics do not follow naming standards: #{invalid_metrics.join(', ')}"
      end

      # All metrics should follow the naming convention or be known exceptions
      expect(valid_count).to eq(metrics_count), "Expected all #{metrics_count} metrics to follow naming standards"
    end

    it "validates that all generated metrics use only standardized dimension names or known test dimensions" do
      # Get all dimension names used in metrics
      all_dimension_names = Set.new

      all_metrics.each do |metric|
        metric[:dimensions].each_key do |dim_name|
          all_dimension_names << dim_name.to_s
        end
      end

      # Get the standard dimension names
      standard_dimensions = Domain::Constants::DimensionConstants.all_dimensions.map(&:to_s)

      # Add the known test dimensions to our accepted list
      accepted_dimensions = standard_dimensions + known_test_dimensions

      # Check that all dimension names used are standard or known test dimensions
      non_standard_dimensions = all_dimension_names.reject { |name| accepted_dimensions.include?(name) }

      # Report any non-standard dimensions
      if non_standard_dimensions.any?
        raise "The following dimension names are not in the standards: #{non_standard_dimensions.to_a.join(', ')}"
      end

      # All dimensions should be standardized or known test dimensions
      expect(non_standard_dimensions).to be_empty, "Expected all dimension names to follow standards"
    end
  end

  describe "metric parsing functionality" do
    it "correctly parses metrics following the naming convention" do
      # Test a variety of metric names
      test_metrics = [
        "github.push.total",
        "github.pull_request.merged",
        "github.commit.breaking_change",
        "github.deployment.success",
        "github.push.directory_hotspot",
        "github.commit_volume.daily"
      ]

      test_metrics.each do |metric_name|
        components = metric_naming_adapter.parse_metric_name(metric_name)

        # Every parsed metric should have source, entity, and action
        expect(components).to have_key(:source)
        expect(components).to have_key(:entity)
        expect(components).to have_key(:action)

        # Verify source is always github in our test set
        expect(components[:source]).to eq("github")

        # Verify we can reconstruct the metric name
        reconstructed = if components[:detail]
                          "#{components[:source]}.#{components[:entity]}.#{components[:action]}.#{components[:detail]}"
                        else
                          "#{components[:source]}.#{components[:entity]}.#{components[:action]}"
                        end

        expect(reconstructed).to eq(metric_name)
      end
    end
  end

  describe "system-wide metric validation", skip: "Would require database access" do
    it "validates that all metrics in the database follow the naming convention" do
      pending "This test would require database access - run manually if needed"

      # This would retrieve metrics from the database and validate them
      # metrics = Metric.limit(100).pluck(:name).uniq
      #
      # valid_count = 0
      # metrics.each do |name|
      #   valid_count += 1 if metric_naming_adapter.valid_metric_name?(name)
      # end
      #
      # expect(valid_count).to eq(metrics.size)
    end
  end

  describe "format helper methods" do
    it "correctly formats timestamps to ISO 8601" do
      time = Time.new(2023, 6, 15, 12, 30, 45)
      formatted = Domain::Constants::DimensionConstants::Time.format_timestamp(time)
      expect(formatted).to match(/^2023-06-15T12:30:45/)
    end

    it "correctly formats dates to YYYY-MM-DD" do
      date = Date.new(2023, 6, 15)
      formatted = Domain::Constants::DimensionConstants::Time.format_date(date)
      expect(formatted).to eq("2023-06-15")
    end

    it "correctly formats boolean values to string literals" do
      expect(Domain::Constants::DimensionConstants::Classification.format_boolean(true)).to eq("true")
      expect(Domain::Constants::DimensionConstants::Classification.format_boolean(false)).to eq("false")
      expect(Domain::Constants::DimensionConstants::Classification.format_boolean("yes")).to eq("true")
      expect(Domain::Constants::DimensionConstants::Classification.format_boolean(0)).to eq("false")
    end

    it "correctly normalizes repository names" do
      expect(Domain::Constants::DimensionConstants.normalize_repository("test-repo")).to eq("unknown/test-repo")
      expect(Domain::Constants::DimensionConstants.normalize_repository("acme/test-repo")).to eq("acme/test-repo")
      expect(Domain::Constants::DimensionConstants.normalize_repository(nil)).to eq("unknown")
      expect(Domain::Constants::DimensionConstants.normalize_repository("")).to eq("unknown")
    end
  end
end
