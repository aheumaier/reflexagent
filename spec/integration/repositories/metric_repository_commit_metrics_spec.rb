# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repositories::MetricRepository, "#commit_metrics" do
  let(:repository) { described_class.new }
  let(:since_date) { 1.month.ago }
  let(:repo_name) { "example/repo" }

  describe "#hotspot_directories" do
    before do
      # Setup test data in CommitMetric
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the hotspot_directories method on CommitMetric
      allow(CommitMetric).to receive(:hotspot_directories).with(since: since_date, limit: 10).and_return([
                                                                                                           double(
                                                                                                             "HotspotDir1", directory: "app/controllers", change_count: 15
                                                                                                           ),
                                                                                                           double(
                                                                                                             "HotspotDir2", directory: "app/models", change_count: 12
                                                                                                           ),
                                                                                                           double(
                                                                                                             "HotspotDir3", directory: "lib/tasks", change_count: 8
                                                                                                           )
                                                                                                         ])
    end

    it "returns properly formatted directory hotspots" do
      result = repository.hotspot_directories(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check format of first result
      expect(result.first).to include(
        directory: "app/controllers",
        count: 15
      )

      # Verify all directories are included
      directories = result.map { |item| item[:directory] }
      expect(directories).to include("app/controllers", "app/models", "lib/tasks")
    end

    it "accepts a custom limit" do
      # Setup expectation for a custom limit
      allow(CommitMetric).to receive(:hotspot_directories).with(since: since_date, limit: 5).and_return([
                                                                                                          double(
                                                                                                            "HotspotDir1", directory: "app/controllers", change_count: 15
                                                                                                          ),
                                                                                                          double(
                                                                                                            "HotspotDir2", directory: "app/models", change_count: 12
                                                                                                          )
                                                                                                        ])

      result = repository.hotspot_directories(since: since_date, repository: repo_name, limit: 5)

      expect(result.size).to eq(2)
    end
  end

  describe "#hotspot_filetypes" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the hotspot_files_by_extension method on CommitMetric
      allow(CommitMetric).to receive(:hotspot_files_by_extension).with(since: since_date, limit: 10).and_return([
                                                                                                                  double(
                                                                                                                    "HotspotExt1", filetype: "rb", change_count: 25
                                                                                                                  ),
                                                                                                                  double(
                                                                                                                    "HotspotExt2", filetype: "js", change_count: 18
                                                                                                                  ),
                                                                                                                  double(
                                                                                                                    "HotspotExt3", filetype: "css", change_count: 10
                                                                                                                  )
                                                                                                                ])
    end

    it "returns properly formatted file type hotspots" do
      result = repository.hotspot_filetypes(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check format of first result
      expect(result.first).to include(
        filetype: "rb",
        count: 25
      )

      # Verify all filetypes are included
      filetypes = result.map { |item| item[:filetype] }
      expect(filetypes).to include("rb", "js", "css")
    end
  end

  describe "#commit_type_distribution" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the commit_type_distribution method on CommitMetric
      allow(CommitMetric).to receive(:commit_type_distribution).with(since: since_date).and_return([
                                                                                                     double(
                                                                                                       "TypeDist1", commit_type: "feat", count: 12
                                                                                                     ),
                                                                                                     double(
                                                                                                       "TypeDist2", commit_type: "fix", count: 18
                                                                                                     ),
                                                                                                     double(
                                                                                                       "TypeDist3", commit_type: "chore", count: 7
                                                                                                     )
                                                                                                   ])
    end

    it "returns properly formatted commit type distribution" do
      result = repository.commit_type_distribution(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check format of first result
      expect(result.first).to include(
        type: "feat",
        count: 12
      )

      # Verify all types are included
      types = result.map { |item| item[:type] }
      expect(types).to include("feat", "fix", "chore")
    end
  end

  describe "#author_activity" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the author_activity method on CommitMetric
      allow(CommitMetric).to receive(:author_activity).with(since: since_date, limit: 10).and_return([
                                                                                                       double(
                                                                                                         "AuthorActivity1", author: "dev1", commit_count: 25
                                                                                                       ),
                                                                                                       double(
                                                                                                         "AuthorActivity2", author: "dev2", commit_count: 15
                                                                                                       ),
                                                                                                       double(
                                                                                                         "AuthorActivity3", author: "dev3", commit_count: 10
                                                                                                       )
                                                                                                     ])
    end

    it "returns properly formatted author activity" do
      result = repository.author_activity(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check format of first result
      expect(result.first).to include(
        author: "dev1",
        commit_count: 25
      )

      # Verify all authors are included
      authors = result.map { |item| item[:author] }
      expect(authors).to include("dev1", "dev2", "dev3")
    end
  end

  describe "#lines_changed_by_author" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the lines_changed_by_author method on CommitMetric
      allow(CommitMetric).to receive(:lines_changed_by_author).with(since: since_date).and_return([
                                                                                                    double(
                                                                                                      "LinesChanged1", author: "dev1", lines_added: 500, lines_deleted: 200
                                                                                                    ),
                                                                                                    double(
                                                                                                      "LinesChanged2", author: "dev2", lines_added: 300, lines_deleted: 100
                                                                                                    ),
                                                                                                    double(
                                                                                                      "LinesChanged3", author: "dev3", lines_added: 150, lines_deleted: 75
                                                                                                    )
                                                                                                  ])
    end

    it "returns properly formatted lines changed by author" do
      result = repository.lines_changed_by_author(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check format of first result
      expect(result.first).to include(
        author: "dev1",
        lines_added: 500,
        lines_deleted: 200,
        lines_changed: 700 # Sum of added and deleted
      )

      # Verify all authors are included
      authors = result.map { |item| item[:author] }
      expect(authors).to include("dev1", "dev2", "dev3")

      # Verify lines_changed is properly calculated
      expect(result[1][:lines_changed]).to eq(400) # 300 + 100
      expect(result[2][:lines_changed]).to eq(225) # 150 + 75
    end
  end

  describe "#breaking_changes_by_author" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the breaking_changes_by_author method on CommitMetric
      allow(CommitMetric).to receive(:breaking_changes_by_author).with(since: since_date).and_return([
                                                                                                       double(
                                                                                                         "BreakingChanges1", author: "dev1", breaking_count: 3
                                                                                                       ),
                                                                                                       double(
                                                                                                         "BreakingChanges2", author: "dev2", breaking_count: 1
                                                                                                       )
                                                                                                     ])
    end

    it "returns properly formatted breaking changes by author" do
      result = repository.breaking_changes_by_author(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)

      # Check format of first result
      expect(result.first).to include(
        author: "dev1",
        breaking_count: 3
      )

      # Verify all authors are included
      authors = result.map { |item| item[:author] }
      expect(authors).to include("dev1", "dev2")
    end
  end

  describe "#commit_activity_by_day" do
    before do
      # Setup test data
      allow(CommitMetric).to receive(:since).with(since_date).and_return(CommitMetric)
      allow(CommitMetric).to receive(:by_repository).with(repo_name).and_return(CommitMetric)

      # Mock the commit_activity_by_day method on CommitMetric
      today = Date.today
      allow(CommitMetric).to receive(:commit_activity_by_day).with(since: since_date).and_return([
                                                                                                   double(
                                                                                                     "DayActivity1", day: today - 2, commit_count: 5
                                                                                                   ),
                                                                                                   double(
                                                                                                     "DayActivity2", day: today - 1, commit_count: 8
                                                                                                   ),
                                                                                                   double(
                                                                                                     "DayActivity3", day: today, commit_count: 3
                                                                                                   )
                                                                                                 ])
    end

    it "returns properly formatted commit activity by day" do
      result = repository.commit_activity_by_day(since: since_date, repository: repo_name)

      expect(result).to be_an(Array)
      expect(result.size).to eq(3)

      # Check that each item has the right format
      result.each do |item|
        expect(item).to have_key(:date)
        expect(item).to have_key(:commit_count)
      end

      # Check that commit counts are correct
      commit_counts = result.map { |item| item[:commit_count] }
      expect(commit_counts).to include(5, 8, 3)
    end
  end
end
