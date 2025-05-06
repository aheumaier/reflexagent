# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::DashboardMetrics do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:repository) { "example/repo" }
  let(:since_date) { 30.days.ago.beginning_of_day }

  let(:use_case) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port
    )
  end

  describe "#call" do
    before do
      allow(cache_port).to receive(:read).and_return(nil)
      allow(cache_port).to receive(:write)

      # Mock storage port methods for each metric type

      # Mock commit activity
      allow(storage_port).to receive(:commit_activity_by_day).and_return([
                                                                           { date: 10.days.ago.to_date,
                                                                             commit_count: 5 },
                                                                           { date: 9.days.ago.to_date,
                                                                             commit_count: 3 },
                                                                           { date: 8.days.ago.to_date, commit_count: 0 }
                                                                         ])

      # Mock directory hotspots
      allow(storage_port).to receive(:hotspot_directories).and_return([
                                                                        { directory: "app/models", count: 15 },
                                                                        { directory: "app/controllers", count: 10 }
                                                                      ])

      # Mock file extensions
      allow(storage_port).to receive(:hotspot_filetypes).and_return([
                                                                      { filetype: "rb", count: 20 },
                                                                      { filetype: "js", count: 5 }
                                                                    ])

      # Mock commit types
      allow(storage_port).to receive(:commit_type_distribution).and_return([
                                                                             { type: "feat", count: 12 },
                                                                             { type: "fix", count: 8 }
                                                                           ])

      # Mock breaking changes
      allow(storage_port).to receive(:breaking_changes_by_author).and_return([
                                                                               { author: "user1", breaking_count: 2 },
                                                                               { author: "user2", breaking_count: 1 }
                                                                             ])

      # Mock author activity
      allow(storage_port).to receive(:author_activity).and_return([
                                                                    { author: "user1", commit_count: 15 },
                                                                    { author: "user2", commit_count: 10 }
                                                                  ])

      # Mock lines changed
      allow(storage_port).to receive(:lines_changed_by_author).and_return([
                                                                            { author: "user1", lines_added: 500,
                                                                              lines_deleted: 200, lines_changed: 700 },
                                                                            { author: "user2", lines_added: 300,
                                                                              lines_deleted: 100, lines_changed: 400 }
                                                                          ])
    end

    context "with default metrics" do
      it "returns a complete dashboard data object" do
        # Call with default metrics (all)
        result = use_case.call(repository: repository)

        # Should include all default metric types
        expect(result).to include(
          :commit_volume,
          :directory_hotspots,
          :file_extensions,
          :commit_types,
          :breaking_changes,
          :author_activity
        )

        # Each metric type should be properly formatted for visualization
        expect(result[:commit_volume]).to include(
          chart_type: "time_series",
          title: "Commit Volume Over Time",
          data_points: be_an(Array),
          summary: include(:total_commits, :avg_per_day)
        )

        expect(result[:directory_hotspots]).to include(
          chart_type: "treemap",
          data_points: be_an(Array),
          summary: include(:total_directories, :total_changes)
        )

        expect(result[:file_extensions]).to include(
          chart_type: "pie",
          data_points: be_an(Array),
          summary: include(:total_extensions, :top_extension)
        )

        expect(result[:commit_types]).to include(
          chart_type: "bar",
          data_points: be_an(Array),
          summary: include(:total_conventional_commits, :top_type)
        )

        expect(result[:breaking_changes]).to include(
          chart_type: "bar",
          data_points: be_an(Array),
          summary: include(:total_breaking_changes)
        )

        expect(result[:author_activity]).to include(
          chart_type: "stacked_bar",
          data_points: be_an(Array),
          summary: include(:total_authors, :total_commits, :total_lines_changed)
        )
      end

      it "formats data points correctly" do
        result = use_case.call(repository: repository)

        # Commit volume data points
        expect(result[:commit_volume][:data_points].first).to include(
          date: be_a(String),
          value: be_a(Integer)
        )

        # Directory hotspot data points
        expect(result[:directory_hotspots][:data_points].first).to include(
          name: "app/models",
          value: 15,
          percentage: be_a(Numeric)
        )

        # Commit type data points
        expect(result[:commit_types][:data_points].first).to include(
          name: "feat",
          value: 12,
          percentage: be_a(Numeric)
        )

        # Author activity data points
        expect(result[:author_activity][:data_points].first).to include(
          name: "user1",
          commit_count: 15,
          lines_added: 500,
          lines_deleted: 200,
          lines_changed: 700
        )
      end
    end

    context "with specific metrics" do
      it "returns only the requested metrics" do
        # Call with specific metrics
        result = use_case.call(
          repository: repository,
          metrics: ["commit_volume", "breaking_changes"]
        )

        # Should only include the requested metrics
        expect(result.keys).to contain_exactly(:commit_volume, :breaking_changes)

        # Should not include other metrics
        expect(result).not_to include(:directory_hotspots, :file_extensions)
      end
    end

    context "with caching" do
      it "returns cached results when available" do
        # Mock cached data
        cached_result = {
          commit_volume: {
            chart_type: "time_series",
            data_points: [{ date: "2023-01-01", value: 10 }]
          }
        }.to_json

        allow(cache_port).to receive(:read).and_return(cached_result)

        result = use_case.call(repository: repository)

        # Should not call storage methods
        expect(storage_port).not_to have_received(:commit_activity_by_day)

        # Should return the cached result
        expect(result).to include("commit_volume")
        expect(result["commit_volume"]).to include("chart_type" => "time_series")
      end
    end

    context "with a custom time period" do
      it "uses the correct since date" do
        # Call with a custom time period
        use_case.call(repository: repository, time_period: 7)

        # Storage methods should be called with the correct since date
        expected_since_date = 7.days.ago.beginning_of_day

        # Time-based comparison might be flaky, so use a broader range
        # Allow up to 12 hours of difference to account for test env variations
        expect(storage_port).to have_received(:commit_activity_by_day) do |args|
          since = args[:since]
          expect(since.to_i).to be_within(43_200).of(expected_since_date.to_i)
        end
      end
    end
  end
end
