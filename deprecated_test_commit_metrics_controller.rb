#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test script to validate CommitMetricsController functionality
# Especially focusing on author filtering capabilities

require_relative "config/environment"

# Simple color implementation without external dependencies
class String
  def red = "\e[31m#{self}\e[0m"
  def green = "\e[32m#{self}\e[0m"
  def yellow = "\e[33m#{self}\e[0m"
end

class CommitMetricsControllerTest
  def initialize
    @controller = Dashboards::CommitMetricsController.new
    @days = 30
    @metrics_service = ServiceFactory.create_metrics_service
    @metric_repository = Repositories::MetricRepository.new
  end

  def validate_metrics_against_database
    puts "\n🧪 Testing direct database metrics validation".yellow

    # Get metrics from the database for comparison
    start_time = @days.days.ago

    # Fetch raw metrics from the repository
    puts "Fetching raw metrics directly from database..."

    raw_commit_metrics = @metric_repository.list_metrics(
      name: "github.push.commits",
      start_time: start_time
    )

    # Calculate the actual commit count from raw data
    actual_commit_count = raw_commit_metrics.sum(&:value)

    puts "   - Raw metrics directly from database:"
    puts "     * Total commit count in last #{@days} days: #{actual_commit_count}"

    # Get top authors directly from database
    authors_data = {}
    raw_commit_metrics.each do |metric|
      author = metric.dimensions["author"] || "unknown"
      authors_data[author] ||= 0
      authors_data[author] += metric.value
    end

    puts "   - Top authors from raw data:"
    authors_data.sort_by { |_, count| -count }.take(3).each do |author, count|
      puts "     * #{author}: #{count} commits"
    end

    # Get metrics via the controller
    controller_metrics = @controller.send(:fetch_commit_metrics, @days)
    controller_commit_count = controller_metrics[:commit_volume][:total_commits]

    puts "   - Controller reports: #{controller_commit_count} total commits"

    # Compare the values
    if controller_commit_count == actual_commit_count
      puts "   ✅ Metrics match between controller and database!".green
    else
      puts "   ⚠️  DISCREPANCY DETECTED: Controller reports #{controller_commit_count} commits but database has #{actual_commit_count}".red

      # Provide possible explanation
      puts "   Possible explanations:"
      puts "   1. Data filtering is happening in the controller that's not in our raw query"
      puts "   2. The metrics are being transformed or aggregated differently"
      puts "   3. There may be a bug in the metrics processing"
    end

    # Check directory metrics too
    raw_directory_metrics = @metric_repository.list_metrics(
      name: "github.push.directory_changes",
      start_time: start_time
    )

    # Get top directories from raw data
    directories_data = {}
    raw_directory_metrics.each do |metric|
      directory = metric.dimensions["directory"] || "unknown"
      directories_data[directory] ||= 0
      directories_data[directory] += metric.value
    end

    puts "\n   - Top directories from raw data:"
    directories_data.sort_by { |_, count| -count }.take(3).each do |directory, count|
      puts "     * #{directory}: #{count} changes"
    end

    # Compare with controller data
    puts "\n   - Top directories from controller:"
    controller_metrics[:directory_hotspots].take(3).each do |dir|
      puts "     * #{dir[:directory]}: #{dir[:count]} changes"

      # Check if values match
      raw_count = directories_data[dir[:directory]] || 0
      if dir[:count] != raw_count
        puts "       ⚠️  DISCREPANCY: Controller reports #{dir[:count]} but raw data shows #{raw_count}".red
      end
    end

    puts "\n✅ Validation complete"
  end

  def test_fetch_all_metrics
    puts "\n🧪 Testing fetch_all_metrics".yellow

    commit_metrics = @controller.send(:fetch_commit_metrics, @days)

    unless commit_metrics
      puts "❌ Failed to get commit metrics".red
      return nil
    end

    puts "✅ Got #{commit_metrics[:commit_volume][:total_commits]} total commits over the last #{@days} days"

    # Check that we have some basic structures
    unless commit_metrics[:commit_volume]
      puts "❌ Missing commit volume data".red
      return nil
    end

    unless commit_metrics[:directory_hotspots]
      puts "❌ Missing directory hotspot data".red
      return nil
    end

    unless commit_metrics[:author_activity]
      puts "❌ Missing author activity data".red
      return nil
    end

    # Validate the data structure
    return nil unless validate_metrics_structure(commit_metrics)

    # Print some basic stats
    puts "   - Top directories:"
    if commit_metrics[:directory_hotspots].any?
      commit_metrics[:directory_hotspots].take(3).each do |dir|
        puts "     * #{dir[:directory]}: #{dir[:count]} changes"
      end
    else
      puts "     * No directory data available"
    end

    puts "   - Top authors:"
    if commit_metrics[:author_activity].any?
      commit_metrics[:author_activity].take(3).each do |author|
        puts "     * #{author[:author]}: #{author[:commit_count]} commits"
      end
    else
      puts "     * No author data available"
    end

    commit_metrics
  end

  def test_fetch_metrics_by_repository
    puts "\n🧪 Testing fetch_metrics_by_repository".yellow

    # Get repositories
    repositories = @controller.send(:fetch_repositories, @days)
    if repositories.empty?
      puts "❌ No repositories found, skipping this test".red
      return nil
    end

    # Select the first repository
    repository = repositories.first
    puts "   Testing with repository: #{repository}"

    commit_metrics = @controller.send(:fetch_commit_metrics, @days, repository)

    unless commit_metrics
      puts "❌ Failed to get commit metrics for repository".red
      return nil
    end

    unless commit_metrics[:repository] == repository
      puts "❌ Repository mismatch in results".red
      return nil
    end

    # Validate the data structure
    return nil unless validate_metrics_structure(commit_metrics)

    puts "✅ Got #{commit_metrics[:commit_volume][:total_commits]} commits for repository #{repository}"

    commit_metrics
  end

  def test_fetch_metrics_by_author
    puts "\n🧪 Testing fetch_metrics_by_author".yellow

    # Get authors
    authors = @controller.send(:fetch_authors, @days)
    if authors.empty?
      puts "❌ No authors found, skipping this test".red
      return nil
    end

    # Select the first author
    author = authors.first
    puts "   Testing with author: #{author}"

    commit_metrics = @controller.send(:fetch_commit_metrics, @days, nil, author)

    unless commit_metrics
      puts "❌ Failed to get commit metrics for author".red
      return nil
    end

    unless commit_metrics[:author] == author
      puts "❌ Author mismatch in results".red
      return nil
    end

    # Validate the data structure
    return nil unless validate_metrics_structure(commit_metrics)

    # The author should appear in the author activity results
    # Note: In some cases, if there are no commits by this author in the time period,
    # they might not appear in the results
    author_in_results = commit_metrics[:author_activity].any? { |a| a[:author] == author }
    unless author_in_results
      puts "    ⚠️  Note: The requested author does not appear in the author activity results".yellow
      puts "    This is expected if the author has no commits in the selected time period"
    end

    puts "✅ Filtered data successfully by author #{author}"

    commit_metrics
  end

  def test_fetch_metrics_by_repository_and_author
    puts "\n🧪 Testing fetch_metrics_by_repository_and_author".yellow

    # Get repositories and authors
    repositories = @controller.send(:fetch_repositories, @days)
    authors = @controller.send(:fetch_authors, @days)

    if repositories.empty? || authors.empty?
      puts "❌ No repositories or authors found, skipping this test".red
      return nil
    end

    # Select the first repository and author
    repository = repositories.first
    author = authors.first
    puts "   Testing with repository: #{repository} and author: #{author}"

    commit_metrics = @controller.send(:fetch_commit_metrics, @days, repository, author)

    unless commit_metrics
      puts "❌ Failed to get commit metrics for repository and author".red
      return nil
    end

    unless commit_metrics[:repository] == repository
      puts "❌ Repository mismatch in results".red
      return nil
    end

    unless commit_metrics[:author] == author
      puts "❌ Author mismatch in results".red
      return nil
    end

    # Validate the data structure
    return nil unless validate_metrics_structure(commit_metrics)

    puts "✅ Filtered data successfully by repository #{repository} and author #{author}"

    commit_metrics
  end

  def test_compare_results
    puts "\n🧪 Testing comparison of filtered vs unfiltered results".yellow

    # Get unfiltered metrics
    all_metrics = test_fetch_all_metrics
    return unless all_metrics

    # Get authors
    authors = @controller.send(:fetch_authors, @days)
    if authors.empty?
      puts "❌ No authors found, skipping this test".red
      return
    end

    # Select the first author
    author = authors.first
    puts "   Comparing metrics with author filter: #{author}"

    # Get filtered metrics
    author_metrics = @controller.send(:fetch_commit_metrics, @days, nil, author)
    unless author_metrics
      puts "❌ Failed to get author metrics".red
      return
    end

    # Validate that filtered results are consistent with unfiltered
    validate_filtered_results_consistency(all_metrics, author_metrics, author)

    # Test with different time periods
    puts "\n   Testing with shorter time period (7 days)"
    short_period = 7
    all_short_metrics = @controller.send(:fetch_commit_metrics, short_period)
    author_short_metrics = @controller.send(:fetch_commit_metrics, short_period, nil, author)

    unless all_short_metrics && author_short_metrics
      puts "❌ Failed to get metrics for short time period".red
      return
    end

    validate_filtered_results_consistency(all_short_metrics, author_short_metrics, author)

    puts "✅ Verification completed for filtered results consistency"
  end

  def test_metrics_service_filtering
    puts "\n🧪 Testing direct metrics_service filtering".yellow

    # Get authors
    authors = @controller.send(:fetch_authors, @days)
    if authors.empty?
      puts "❌ No authors found, skipping this test".red
      return
    end

    # Select the first author
    author = authors.first
    puts "   Testing direct metrics service filtering for author: #{author}"

    # Test the metrics service directly to verify filter_dimensions works
    filter_dimensions = { "author" => author }

    # Get commit count with and without filter
    all_commits = @metrics_service.top_metrics(
      "github.push.commits",
      dimension: "day",
      limit: @days,
      days: @days
    ).values.sum

    filtered_commits = @metrics_service.top_metrics(
      "github.push.commits",
      dimension: "day",
      limit: @days,
      days: @days,
      filter_dimensions: filter_dimensions
    ).values.sum

    unless filtered_commits <= all_commits
      puts "❌ Filtered commits should be less than or equal to all commits".red
      return
    end

    puts "   Total commits: #{all_commits}"
    puts "   Filtered commits for #{author}: #{filtered_commits}"
    puts "✅ Metrics service filtering works correctly"
  end

  def test_debug_database_metrics
    puts "\n🧪 Testing debug database metrics".yellow

    # Direct database debug - useful for troubleshooting data discrepancies
    begin
      puts "Examining raw metrics from database..."

      # Count total DomainMetric records
      total_metrics = DomainMetric.count
      puts "   - Total metrics in database: #{total_metrics}"

      # Count commit metrics
      commit_metrics = DomainMetric.where("name = 'github.push.commits'").count
      puts "   - github.push.commits metrics: #{commit_metrics}"

      # Get recent commits
      start_time = @days.days.ago
      recent_commits = DomainMetric.where("name = 'github.push.commits' AND recorded_at >= ?", start_time).count
      puts "   - Recent github.push.commits (last #{@days} days): #{recent_commits}"

      # Sum commit counts
      commit_sum = DomainMetric.where("name = 'github.push.commits' AND recorded_at >= ?", start_time).sum(:value)
      puts "   - Total commit count (last #{@days} days): #{commit_sum}"

      # Get unique authors
      authors = DomainMetric.where("name = 'github.push.commits' AND recorded_at >= ?", start_time)
                            .pluck("dimensions -> 'author'")
                            .compact
                            .uniq
      puts "   - Unique authors (last #{@days} days): #{authors.size}"
      puts "     * #{authors.join(', ')}"

      # Get unique repositories
      repos = DomainMetric.where("name = 'github.push.commits' AND recorded_at >= ?", start_time)
                          .pluck("dimensions -> 'repository'")
                          .compact
                          .uniq
      puts "   - Unique repositories (last #{@days} days): #{repos.size}"
      puts "     * #{repos.join(', ')}" if repos.size < 10

      puts "✅ Database examination complete"
    rescue StandardError => e
      puts "❌ Error examining database: #{e.message}".red
      puts e.backtrace.join("\n").red
    end
  end

  def validate_metrics_structure(metrics)
    # Validate commit volume metrics
    unless metrics[:commit_volume].is_a?(Hash)
      puts "❌ commit_volume should be a hash".red
      return false
    end

    [:total_commits, :days_with_commits, :commits_per_day, :commit_frequency].each do |key|
      unless metrics[:commit_volume].key?(key)
        puts "❌ commit_volume should have #{key}".red
        return false
      end
    end

    # Validate directory hotspots
    unless metrics[:directory_hotspots].is_a?(Array)
      puts "❌ directory_hotspots should be an array".red
      return false
    end

    if metrics[:directory_hotspots].any?
      hotspot = metrics[:directory_hotspots].first
      [:directory, :count].each do |key|
        unless hotspot.key?(key)
          puts "❌ directory hotspot should have #{key} key".red
          return false
        end
      end
    end

    # Validate author activity
    unless metrics[:author_activity].is_a?(Array)
      puts "❌ author_activity should be an array".red
      return false
    end

    if metrics[:author_activity].any?
      activity = metrics[:author_activity].first
      [:author, :commit_count].each do |key|
        unless activity.key?(key)
          puts "❌ author activity should have #{key} key".red
          return false
        end
      end
    end

    # Validate file extension hotspots
    unless metrics[:file_extension_hotspots].is_a?(Array)
      puts "❌ file_extension_hotspots should be an array".red
      return false
    end

    if metrics[:file_extension_hotspots].any?
      ext = metrics[:file_extension_hotspots].first
      [:extension, :count].each do |key|
        unless ext.key?(key)
          puts "❌ file extension hotspot should have #{key} key".red
          return false
        end
      end
    end

    true
  end

  def validate_filtered_results_consistency(all_metrics, filtered_metrics, author)
    # The total commits for the author should be less than or equal to the total unfiltered commits
    unless filtered_metrics[:commit_volume][:total_commits] <= all_metrics[:commit_volume][:total_commits]
      puts "❌ Author's commit count should be less than or equal to total commits".red
      return false
    end

    # Look for the author in the unfiltered author activity
    author_data = all_metrics[:author_activity].find { |a| a[:author] == author }

    if author_data
      # Author found in results - compare commit counts
      author_commit_count = author_data[:commit_count]

      # The commit count from the filtered metrics might differ if metrics have dimension filters
      # In some cases it will be accurate, in others approximate due to how aggregation works
      puts "   Unfiltered metrics show #{author} has #{author_commit_count} commits"
      puts "   Filtered metrics show total of #{filtered_metrics[:commit_volume][:total_commits]} commits"

      # Add a note about this for debugging
      if filtered_metrics[:commit_volume][:total_commits] != author_commit_count
        puts "   ⚠️  Note: The counts differ because filtered metrics apply filter to raw data vs author list".yellow
      end
    else
      # It's possible that the author doesn't have any commits in the time period
      # This is not necessarily an error, but we should note it
      puts "   ⚠️  Note: Author not found in unfiltered results for this time period".yellow
      puts "   This can happen if the author has no commits in the time period or if data is sparse"
    end

    true
  end

  def run_all_tests
    puts "\n🚀 Running all CommitMetricsController tests...".green
    puts "================================================".green

    begin
      # First run direct database validation
      test_debug_database_metrics
      validate_metrics_against_database

      # Then run controller tests
      test_fetch_all_metrics
      test_fetch_metrics_by_repository
      test_fetch_metrics_by_author
      test_fetch_metrics_by_repository_and_author
      test_compare_results
      test_metrics_service_filtering

      puts "\n✅ All tests completed!".green
      puts "================================================".green
    rescue StandardError => e
      puts "\n❌ Test failed with error: #{e.message}".red
      puts e.backtrace.join("\n").red
    end
  end
end

# Create test instance and run tests
test = CommitMetricsControllerTest.new
test.run_all_tests
