# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adapters::Metrics::MetricNamingAdapter do
  let(:adapter) { described_class.new }
  let(:event) do
    instance_double(
      "Domain::Event",
      name: "github.push.created",
      source: "github",
      data: {
        repository: {
          full_name: "acme-org/test-repo",
          owner: {
            login: "acme-org"
          }
        },
        sender: {
          login: "test-user"
        }
      }
    )
  end

  describe "#build_metric_name" do
    it "builds a metric name following the convention" do
      name = adapter.build_metric_name(
        source: "github",
        entity: "push",
        action: "total"
      )
      expect(name).to eq("github.push.total")
    end

    it "includes optional detail when provided" do
      name = adapter.build_metric_name(
        source: "github",
        entity: "push",
        action: "total",
        detail: "daily"
      )
      expect(name).to eq("github.push.total.daily")
    end
  end

  describe "#valid_metric_name?" do
    it "validates a correct metric name" do
      expect(adapter.valid_metric_name?("github.push.total")).to be true
      expect(adapter.valid_metric_name?("github.push.total.daily")).to be true
    end

    it "rejects invalid metric names" do
      expect(adapter.valid_metric_name?("github")).to be false
      expect(adapter.valid_metric_name?("github.invalid_entity.total")).to be false
      expect(adapter.valid_metric_name?("github.push.invalid_action")).to be false
      expect(adapter.valid_metric_name?("github.push.total.invalid_detail")).to be false
    end
  end

  describe "#parse_metric_name" do
    it "extracts components from a valid metric name" do
      result = adapter.parse_metric_name("github.push.total")
      expect(result).to include(
        source: "github",
        entity: "push",
        action: "total"
      )
    end

    it "includes detail when present" do
      result = adapter.parse_metric_name("github.push.total.daily")
      expect(result).to include(
        source: "github",
        entity: "push",
        action: "total",
        detail: "daily"
      )
    end

    it "returns empty hash for invalid names" do
      expect(adapter.parse_metric_name("github")).to eq({})
    end
  end

  describe "#build_standard_dimensions" do
    it "extracts standard dimensions from an event" do
      dimensions = adapter.build_standard_dimensions(event)

      expect(dimensions).to include(
        "repository" => "acme-org/test-repo",
        "organization" => "acme-org",
        "source" => "github",
        "author" => "test-user"
      )
    end

    it "merges additional dimensions" do
      dimensions = adapter.build_standard_dimensions(
        event,
        { "branch" => "main", "environment" => "production" }
      )

      expect(dimensions).to include(
        "repository" => "acme-org/test-repo",
        "branch" => "main",
        "environment" => "production"
      )
    end
  end

  describe "#normalize_dimension_name" do
    it "converts camelCase to snake_case" do
      expect(adapter.normalize_dimension_name("repositoryName")).to eq("repository_name")
    end

    it "converts PascalCase to snake_case" do
      expect(adapter.normalize_dimension_name("RepositoryName")).to eq("repository_name")
    end

    it "converts kebab-case to snake_case" do
      expect(adapter.normalize_dimension_name("repository-name")).to eq("repository_name")
    end
  end

  describe "#normalize_dimension_value" do
    it "formats date dimensions" do
      date = Time.new(2023, 1, 15)
      expect(adapter.normalize_dimension_value("date", date)).to eq("2023-01-15")
    end

    it "formats timestamp dimensions" do
      time = Time.new(2023, 1, 15, 12, 30, 45)
      expect(adapter.normalize_dimension_value("timestamp", time)).to match(/2023-01-15T12:30:45/)
    end

    it "normalizes repository names" do
      expect(adapter.normalize_dimension_value("repository", "test-repo")).to eq("unknown/test-repo")
      expect(adapter.normalize_dimension_value("repository", "org/repo")).to eq("org/repo")
    end

    it "formats boolean values" do
      expect(adapter.normalize_dimension_value("conventional", true)).to eq("true")
      expect(adapter.normalize_dimension_value("conventional", "yes")).to eq("true")
      expect(adapter.normalize_dimension_value("conventional", 0)).to eq("false")
    end
  end

  describe "#valid_dimension_name?" do
    it "validates standard dimension names" do
      expect(adapter.valid_dimension_name?("repository")).to be true
      expect(adapter.valid_dimension_name?("author")).to be true
      expect(adapter.valid_dimension_name?("date")).to be true
    end

    it "rejects non-standard dimension names" do
      expect(adapter.valid_dimension_name?("unknown_dimension")).to be false
    end
  end

  describe "#available_sources" do
    it "returns all available sources" do
      sources = adapter.available_sources
      expect(sources).to include("github", "bitbucket", "jira")
    end
  end

  describe "#available_entities" do
    it "returns all available entities" do
      entities = adapter.available_entities
      expect(entities).to include("push", "pull_request", "issue")
    end
  end

  describe "#available_actions" do
    it "returns all available actions" do
      actions = adapter.available_actions
      expect(actions).to include("total", "created", "merged")
    end
  end

  describe "#available_details" do
    it "returns all available details" do
      details = adapter.available_details
      expect(details).to include("daily", "weekly", "monthly")
    end
  end

  describe "#dimension_categories" do
    it "returns all dimension categories" do
      categories = adapter.dimension_categories
      expect(categories).to include(
        "Source", "Time", "Actor", "Content", "Classification", "Measurement"
      )
    end
  end

  describe "#dimensions_in_category" do
    it "returns dimensions for Source category" do
      dimensions = adapter.dimensions_in_category("Source")
      expect(dimensions).to include("repository", "organization", "source")
    end

    it "returns dimensions for Time category" do
      dimensions = adapter.dimensions_in_category("Time")
      expect(dimensions).to include("date", "timestamp", "week")
    end

    it "returns empty array for unknown category" do
      expect(adapter.dimensions_in_category("Unknown")).to eq([])
    end
  end

  describe "#valid_metric_mapping?" do
    it "validates a valid metric name mapping" do
      expect(adapter.valid_metric_mapping?(
               "github.push.commits",
               "github.commit.total"
             )).to be true
    end

    it "rejects mappings with different sources" do
      expect(adapter.valid_metric_mapping?(
               "github.push.total",
               "jira.issue.total"
             )).to be false
    end

    it "rejects mappings to invalid metric names" do
      expect(adapter.valid_metric_mapping?(
               "github.push.total",
               "github.invalid_entity.total"
             )).to be false
    end
  end
end
