# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "Metrics Dimensions Configuration" do
  let(:config_path) { Rails.root.join("config/metrics_dimensions.yml") }
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:github_classifier) { Domain::Classifiers::GithubEventClassifier.new(dimension_extractor) }

  it "has a valid configuration file" do
    expect(File.exist?(config_path)).to be(true)
    config = YAML.load_file(config_path)
    expect(config).to be_a(Hash)
    expect(config["commit_dimensions"]).to be_a(Hash)
  end

  context "conventional commit dimensions" do
    let(:commit) { { message: "feat(api)!: add new endpoint" } }
    let(:expected_keys) do
      [
        "commit_type",
        "commit_scope",
        "commit_breaking",
        "commit_description",
        "commit_conventional"
      ]
    end

    it "defines all conventional commit dimensions used in the code" do
      config = YAML.load_file(config_path)
      commit_dimensions = config["commit_dimensions"]

      # Get the conventional commit keys defined in config
      conventional_keys = expected_keys.select { |key| commit_dimensions.key?(key) }

      # Make sure all expected keys are present
      expect(conventional_keys.sort).to eq(expected_keys.sort)

      # Verify the extractor actually returns these keys
      result = dimension_extractor.extract_conventional_commit_parts(commit)
      expected_keys.each do |key|
        expect(result).to have_key(key.to_sym)
      end
    end
  end

  context "file change dimensions" do
    let(:push_event) do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        {
          added: ["src/users/login.rb", "src/users/logout.rb"],
          modified: ["src/app.rb", "config/routes.rb"],
          removed: ["old_file.rb"]
        }
      ]
      event
    end

    let(:expected_keys) do
      [
        "files_added",
        "files_modified",
        "files_removed",
        "file_paths_added",
        "file_paths_modified",
        "file_paths_removed",
        "directory_hotspots",
        "top_directory",
        "top_directory_count",
        "extension_hotspots",
        "top_extension",
        "top_extension_count"
      ]
    end

    it "defines all file change dimensions used in the code" do
      config = YAML.load_file(config_path)
      commit_dimensions = config["commit_dimensions"]

      # Get the file change keys defined in config
      file_change_keys = expected_keys.select { |key| commit_dimensions.key?(key) }

      # Make sure all expected keys are present
      expect(file_change_keys.sort).to eq(expected_keys.sort)

      # Verify the extractor actually returns these keys
      result = dimension_extractor.extract_file_changes(push_event)

      # Basic file counts
      expect(result).to have_key(:files_added)
      expect(result).to have_key(:files_modified)
      expect(result).to have_key(:files_removed)

      # File paths
      expect(result).to have_key(:file_paths_added)
      expect(result).to have_key(:file_paths_modified)
      expect(result).to have_key(:file_paths_removed)

      # Directory analysis
      dir_analysis = dimension_extractor.analyze_directories(
        result[:file_paths_added] + result[:file_paths_modified] + result[:file_paths_removed]
      )
      expect(dir_analysis).to have_key(:directory_hotspots)
      expect(dir_analysis).to have_key(:top_directory)
      expect(dir_analysis).to have_key(:top_directory_count)

      # Extension analysis
      ext_analysis = dimension_extractor.analyze_extensions(
        result[:file_paths_added] + result[:file_paths_modified] + result[:file_paths_removed]
      )
      expect(ext_analysis).to have_key(:extension_hotspots)
      expect(ext_analysis).to have_key(:top_extension)
      expect(ext_analysis).to have_key(:top_extension_count)
    end
  end

  context "code volume dimensions" do
    let(:push_event) do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: 10, deletions: 5 } },
        { stats: { additions: 20, deletions: 8 } }
      ]
      event
    end

    let(:expected_keys) do
      [
        "code_additions",
        "code_deletions",
        "code_churn"
      ]
    end

    it "defines all code volume dimensions used in the code" do
      config = YAML.load_file(config_path)
      commit_dimensions = config["commit_dimensions"]

      # Get the code volume keys defined in config
      volume_keys = expected_keys.select { |key| commit_dimensions.key?(key) }

      # Make sure all expected keys are present
      expect(volume_keys.sort).to eq(expected_keys.sort)

      # Verify the extractor actually returns these keys
      result = dimension_extractor.extract_code_volume(push_event)

      expected_keys.each do |key|
        expect(result).to have_key(key.to_sym)
      end
    end
  end

  context "when classifying GitHub push events" do
    let(:push_event) do
      FactoryBot.build(
        :event,
        name: "github.push",
        source: "github",
        data: {
          repository: { full_name: "example/repo" },
          commits: [
            {
              id: "abc123",
              message: "feat(users): add login functionality",
              added: ["src/users/login.rb"],
              modified: ["src/app.rb"],
              removed: [],
              stats: { additions: 100, deletions: 20 }
            }
          ],
          ref: "refs/heads/main",
          sender: { login: "octocat" }
        }
      )
    end

    it "uses the configured dimensions for metrics" do
      result = github_classifier.classify(push_event)

      # Check that metrics use the dimensions defined in config
      result[:metrics].each do |metric|
        # Each metric should have dimensions that are documented
        metric[:dimensions].each_key do |dim_key|
          # Skip general dimensions like repository, organization, source, etc.
          next if [:repository, :organization, :source, :branch, :author, :type, :scope, :directory,
                   :filetype].include?(dim_key)

          # Convert symbol to string for comparison with config
          dim_key_str = dim_key.to_s

          # The dimension should either be a commit dimension or a general dimension
          config = YAML.load_file(config_path)
          commit_dimensions = config["commit_dimensions"] || {}

          # If it's not a general dimension, it should be documented in config
          next if ["repository", "organization", "source", "branch", "author", "type", "scope", "directory",
                   "filetype"].include?(dim_key_str)

          expect(commit_dimensions.key?(dim_key_str)).to be(true),
                                                         "Dimension '#{dim_key_str}' used in metrics but not documented in config"
        end
      end
    end
  end
end
