# frozen_string_literal: true

require "rails_helper"

RSpec.describe UseCases::AnalyzeCommits do
  let(:storage_port) { instance_double("StoragePort") }
  let(:cache_port) { instance_double("CachePort") }
  let(:dimension_extractor) { instance_double("Domain::Extractors::DimensionExtractor") }

  let(:repository) { "example/repo" }
  let(:since_date) { 30.days.ago }

  let(:use_case) do
    described_class.new(
      storage_port: storage_port,
      cache_port: cache_port,
      dimension_extractor: dimension_extractor
    )
  end

  describe "#call" do
    context "when metrics are found" do
      before do
        # Mock commit metrics for the repository
        allow(cache_port).to receive(:read).and_return(nil)
        allow(cache_port).to receive(:write)

        # Mock example metrics
        allow(storage_port).to receive(:list_metrics).and_return([
                                                                   {
                                                                     name: "github.push.total",
                                                                     value: 1,
                                                                     dimensions: { repository: repository },
                                                                     timestamp: 5.days.ago
                                                                   },
                                                                   {
                                                                     name: "github.commit.type",
                                                                     value: 1,
                                                                     dimensions: { repository: repository,
                                                                                   commit_type: "feat" },
                                                                     timestamp: 5.days.ago
                                                                   }
                                                                 ])

        # Mock hotspot directories
        allow(storage_port).to receive(:hotspot_directories).and_return([
                                                                          { directory: "app/models", count: 15 },
                                                                          { directory: "app/controllers", count: 10 }
                                                                        ])

        # Mock hotspot filetypes
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

        # Mock commit activity by day
        allow(storage_port).to receive(:commit_activity_by_day).and_return([
                                                                             { date: 10.days.ago.to_date,
                                                                               commit_count: 5 },
                                                                             { date: 9.days.ago.to_date,
                                                                               commit_count: 3 },
                                                                             { date: 8.days.ago.to_date,
                                                                               commit_count: 0 }
                                                                           ])
      end

      it "returns a complete analysis result" do
        result = use_case.call(repository: repository, since: since_date)

        # Check that result contains all expected sections
        expect(result).to include(
          :directory_hotspots,
          :file_extension_hotspots,
          :commit_types,
          :breaking_changes,
          :author_activity,
          :commit_volume,
          :code_churn
        )

        # Check directory hotspots
        expect(result[:directory_hotspots]).to be_an(Array)
        expect(result[:directory_hotspots].first).to include(
          directory: "app/models",
          count: 15,
          percentage: be_a(Numeric)
        )

        # Check file extension hotspots
        expect(result[:file_extension_hotspots]).to be_an(Array)
        expect(result[:file_extension_hotspots].first).to include(
          extension: "rb",
          count: 20
        )

        # Check commit types
        expect(result[:commit_types]).to be_an(Array)
        expect(result[:commit_types].first).to include(
          type: "feat",
          count: 12
        )

        # Check breaking changes
        expect(result[:breaking_changes]).to include(
          total: 3,
          by_author: be_an(Array)
        )

        # Check author activity
        expect(result[:author_activity]).to be_an(Array)
        expect(result[:author_activity].first).to include(
          author: "user1",
          commit_count: 15,
          lines_added: 500
        )

        # Check commit volume
        expect(result[:commit_volume]).to include(
          total_commits: 8,
          days_with_commits: 2,
          commits_per_day: be_a(Numeric)
        )
      end

      it "uses cached results when available" do
        # Create a JSON-serialized result to mimic what would be in the cache
        cached_result = {
          "directory_hotspots" => [{ "directory" => "cached/dir", "count" => 5 }],
          "file_extension_hotspots" => [],
          "commit_types" => [],
          "breaking_changes" => { "total" => 0, "by_author" => [] },
          "author_activity" => [],
          "commit_volume" => { "total_commits" => 0 },
          "code_churn" => { "additions" => 0 }
        }.to_json

        allow(cache_port).to receive(:read).and_return(cached_result)

        result = use_case.call(repository: repository, since: since_date)

        # Should not call the storage port to get metrics
        expect(storage_port).not_to have_received(:list_metrics)

        # Result should be the parsed JSON with string keys
        expect(result).to be_a(Hash)
        expect(result["directory_hotspots"]).to be_an(Array)
        expect(result["directory_hotspots"].first).to include("directory" => "cached/dir")
      end
    end

    context "when no metrics are found" do
      before do
        allow(cache_port).to receive(:read).and_return(nil)
        allow(cache_port).to receive(:write)
        allow(storage_port).to receive(:list_metrics).and_return([])
      end

      it "returns an empty analysis result" do
        result = use_case.call(repository: repository, since: since_date)

        expect(result[:directory_hotspots]).to be_empty
        expect(result[:file_extension_hotspots]).to be_empty
        expect(result[:commit_types]).to be_empty
        expect(result[:breaking_changes][:total]).to eq(0)
        expect(result[:breaking_changes][:by_author]).to be_empty
        expect(result[:author_activity]).to be_empty
        expect(result[:commit_volume][:total_commits]).to eq(0)
      end
    end
  end
end
