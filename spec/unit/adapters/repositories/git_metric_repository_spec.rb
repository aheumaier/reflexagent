# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::GitMetricRepository do
  let(:metric_naming_port) { double("MetricNamingPort") }
  let(:logger_port) { double("LoggerPort", debug: nil, info: nil, warn: nil, error: nil) }
  let(:repository) { described_class.new(metric_naming_port: metric_naming_port, logger_port: logger_port) }

  # Shared test data and mocks
  let(:since_time) { 30.days.ago }
  let(:repository_name) { "test-org/test-repo" }
  let(:source_name) { "github" }
  let(:limit_value) { 5 }

  # Mock query object
  let(:base_query) { double("ActiveRecord::Relation") }

  # Common setup that stubs the protected build_base_query method
  before do
    allow(repository).to receive(:build_base_query).and_return(base_query)
  end

  describe "#hotspot_directories" do
    let(:directory_hotspots) do
      [
        double("DirectoryHotspot", directory: "app/controllers", change_count: 25),
        double("DirectoryHotspot", directory: "app/models", change_count: 18)
      ]
    end

    it "finds hotspot directories for a given time period" do
      # Arrange
      allow(base_query).to receive(:hotspot_directories).with(since: since_time,
                                                              limit: 10).and_return(directory_hotspots)

      # Act
      result = repository.hotspot_directories(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ directory: "app/controllers", count: 25 })
      expect(result.last).to eq({ directory: "app/models", count: 18 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:hotspot_directories).and_return(directory_hotspots)

      # Act
      repository.hotspot_directories(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:hotspot_directories).and_return(directory_hotspots)

      # Act
      repository.hotspot_directories(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "limits results if requested" do
      # Arrange
      allow(base_query).to receive(:hotspot_directories).with(since: since_time,
                                                              limit: limit_value).and_return(directory_hotspots)

      # Act
      repository.hotspot_directories(since: since_time, limit: limit_value)

      # Assert
      expect(base_query).to have_received(:hotspot_directories).with(since: since_time, limit: limit_value)
    end
  end

  describe "#hotspot_filetypes" do
    let(:filetype_hotspots) do
      [
        double("FiletypeHotspot", filetype: "rb", change_count: 42),
        double("FiletypeHotspot", filetype: "js", change_count: 27)
      ]
    end

    it "finds hotspot file types for a given time period" do
      # Arrange
      allow(base_query).to receive(:hotspot_files_by_extension).with(since: since_time,
                                                                     limit: 10).and_return(filetype_hotspots)

      # Act
      result = repository.hotspot_filetypes(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ filetype: "rb", count: 42 })
      expect(result.last).to eq({ filetype: "js", count: 27 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:hotspot_files_by_extension).and_return(filetype_hotspots)

      # Act
      repository.hotspot_filetypes(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:hotspot_files_by_extension).and_return(filetype_hotspots)

      # Act
      repository.hotspot_filetypes(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "limits results if requested" do
      # Arrange
      allow(base_query).to receive(:hotspot_files_by_extension).with(since: since_time,
                                                                     limit: limit_value).and_return(filetype_hotspots)

      # Act
      repository.hotspot_filetypes(since: since_time, limit: limit_value)

      # Assert
      expect(base_query).to have_received(:hotspot_files_by_extension).with(since: since_time, limit: limit_value)
    end
  end

  describe "#commit_type_distribution" do
    let(:commit_types) do
      [
        double("CommitType", commit_type: "feature", count: 15),
        double("CommitType", commit_type: "fix", count: 8),
        double("CommitType", commit_type: "chore", count: 4)
      ]
    end

    it "finds distribution of commit types for a given time period" do
      # Arrange
      allow(base_query).to receive(:commit_type_distribution).with(since: since_time).and_return(commit_types)

      # Act
      result = repository.commit_type_distribution(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
      expect(result.first).to eq({ type: "feature", count: 15 })
      expect(result.last).to eq({ type: "chore", count: 4 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:commit_type_distribution).and_return(commit_types)

      # Act
      repository.commit_type_distribution(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:commit_type_distribution).and_return(commit_types)

      # Act
      repository.commit_type_distribution(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end
  end

  describe "#author_activity" do
    let(:author_activities) do
      [
        double("AuthorActivity", author: "alice", commit_count: 23),
        double("AuthorActivity", author: "bob", commit_count: 17)
      ]
    end

    it "finds most active authors for a given time period" do
      # Arrange
      allow(base_query).to receive(:author_activity).with(since: since_time, limit: 10).and_return(author_activities)

      # Act
      result = repository.author_activity(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ author: "alice", commit_count: 23 })
      expect(result.last).to eq({ author: "bob", commit_count: 17 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:author_activity).and_return(author_activities)

      # Act
      repository.author_activity(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:author_activity).and_return(author_activities)

      # Act
      repository.author_activity(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "limits results if requested" do
      # Arrange
      allow(base_query).to receive(:author_activity).with(since: since_time,
                                                          limit: limit_value).and_return(author_activities)

      # Act
      repository.author_activity(since: since_time, limit: limit_value)

      # Assert
      expect(base_query).to have_received(:author_activity).with(since: since_time, limit: limit_value)
    end
  end

  describe "#lines_changed_by_author" do
    let(:author_lines) do
      [
        double("AuthorLines", author: "alice", lines_added: 120, lines_deleted: 50),
        double("AuthorLines", author: "bob", lines_added: 80, lines_deleted: 40)
      ]
    end

    it "finds lines changed by author for a given time period" do
      # Arrange
      allow(base_query).to receive(:lines_changed_by_author).with(since: since_time).and_return(author_lines)

      # Act
      result = repository.lines_changed_by_author(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ author: "alice", lines_added: 120, lines_deleted: 50, lines_changed: 170 })
      expect(result.last).to eq({ author: "bob", lines_added: 80, lines_deleted: 40, lines_changed: 120 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:lines_changed_by_author).and_return(author_lines)

      # Act
      repository.lines_changed_by_author(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:lines_changed_by_author).and_return(author_lines)

      # Act
      repository.lines_changed_by_author(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end
  end

  describe "#breaking_changes_by_author" do
    let(:breaking_changes) do
      [
        double("BreakingChanges", author: "alice", breaking_count: 3),
        double("BreakingChanges", author: "bob", breaking_count: 1)
      ]
    end

    it "finds breaking changes by author for a given time period" do
      # Arrange
      allow(base_query).to receive(:breaking_changes_by_author).with(since: since_time).and_return(breaking_changes)

      # Act
      result = repository.breaking_changes_by_author(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ author: "alice", breaking_count: 3 })
      expect(result.last).to eq({ author: "bob", breaking_count: 1 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:breaking_changes_by_author).and_return(breaking_changes)

      # Act
      repository.breaking_changes_by_author(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:breaking_changes_by_author).and_return(breaking_changes)

      # Act
      repository.breaking_changes_by_author(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end
  end

  describe "#commit_activity_by_day" do
    let(:daily_activities) do
      [
        double("DailyActivity", day: Date.today - 3.days, commit_count: 12),
        double("DailyActivity", day: Date.today - 2.days, commit_count: 8)
      ]
    end

    it "finds commit activity by day for a given time period" do
      # Arrange
      allow(base_query).to receive(:commit_activity_by_day).with(since: since_time).and_return(daily_activities)

      # Act
      result = repository.commit_activity_by_day(since: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first).to eq({ date: daily_activities.first.day, commit_count: 12 })
      expect(result.last).to eq({ date: daily_activities.last.day, commit_count: 8 })
    end

    it "applies source system filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: source_name, repository: nil
      ).and_return(base_query)
      allow(base_query).to receive(:commit_activity_by_day).and_return(daily_activities)

      # Act
      repository.commit_activity_by_day(since: since_time, source: source_name)

      # Assert - verification is in the expect().to receive() call above
    end

    it "applies repository filter if provided" do
      # Arrange
      expect(repository).to receive(:build_base_query).with(
        since: since_time, source: nil, repository: repository_name
      ).and_return(base_query)
      allow(base_query).to receive(:commit_activity_by_day).and_return(daily_activities)

      # Act
      repository.commit_activity_by_day(since: since_time, repository: repository_name)

      # Assert - verification is in the expect().to receive() call above
    end
  end

  describe "#get_active_repositories" do
    let(:connection) { double("ActiveRecord::Connection") }
    let(:query_result) do
      [
        { "repository_name" => "org/repo1" },
        { "repository_name" => "org/repo2" }
      ]
    end

    before do
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(connection).to receive(:exec_query).and_return(query_result)
    end

    it "gets active repositories with DB-level aggregation" do
      # Act
      result = repository.get_active_repositories(start_time: since_time)

      # Assert
      expect(result).to be_an(Array)
      expect(result).to eq(["org/repo1", "org/repo2"])
      expect(connection).to have_received(:exec_query)
    end

    it "applies source system filter if provided" do
      # Act
      repository.get_active_repositories(start_time: since_time, source: source_name)

      # Assert
      expect(connection).to have_received(:exec_query) do |sql, _, _|
        expect(sql).to include("AND name LIKE '#{source_name}.%'")
      end
    end

    it "limits results if requested" do
      # Arrange
      limit = 5

      # Act
      repository.get_active_repositories(start_time: since_time, limit: limit)

      # Assert
      expect(connection).to have_received(:exec_query) do |sql, _, params|
        expect(sql).to include("LIMIT ?")
        expect(params.last).to eq(limit)
      end
    end

    it "applies pagination if requested" do
      # Arrange
      page = 2
      per_page = 10

      # Act
      repository.get_active_repositories(start_time: since_time, page: page, per_page: per_page)

      # Assert
      expect(connection).to have_received(:exec_query) do |sql, _, params|
        expect(sql).to include("LIMIT ? OFFSET ?")
        expect(params[1]).to eq(per_page)
        expect(params[2]).to eq((page - 1) * per_page)
      end
    end

    it "handles database errors gracefully" do
      # Arrange
      allow(connection).to receive(:exec_query).and_raise(StandardError.new("DB error"))
      allow(logger_port).to receive(:error)

      # Act
      result = repository.get_active_repositories(start_time: since_time)

      # Assert
      expect(result).to eq([])
      expect(logger_port).to have_received(:error).at_least(:once)
    end
  end

  describe "#build_base_query" do
    # We need to use the actual implementation for these tests
    before { allow(repository).to receive(:build_base_query).and_call_original }

    # For these tests we need to define a CommitMetric double
    let(:commit_metric_double) { double("CommitMetric") }
    let(:filtered_query) { double("FilteredQuery") }

    before do
      # Stub the CommitMetric constant
      stub_const("CommitMetric", commit_metric_double)
      allow(commit_metric_double).to receive(:since).and_return(base_query)
      allow(base_query).to receive(:by_source).and_return(filtered_query)
      allow(base_query).to receive(:by_repository).and_return(filtered_query)
    end

    it "builds a base query that filters by time period" do
      # Act
      repository.send(:build_base_query, since: since_time)

      # Assert
      expect(commit_metric_double).to have_received(:since).with(since_time)
    end

    it "applies source system filter if provided" do
      # Act
      result = repository.send(:build_base_query, since: since_time, source: source_name)

      # Assert
      expect(base_query).to have_received(:by_source).with(source_name)
      expect(result).to eq(filtered_query)
    end

    it "applies repository filter if provided" do
      # Act
      result = repository.send(:build_base_query, since: since_time, repository: repository_name)

      # Assert
      expect(base_query).to have_received(:by_repository).with(repository_name)
      expect(result).to eq(filtered_query)
    end
  end
end
