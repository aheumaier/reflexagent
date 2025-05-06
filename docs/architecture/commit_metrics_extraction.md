# ADR: Enhanced Commit Data Extraction and Metrics

## Context
Our current event classification system extracts basic information from GitHub push events, including repositories, commit counts, branches, and authors. However, we're missing opportunities to gain deeper insights from commit metadata such as:

1. Commit messages and their structured components (using conventional commits format)
2. Modified file paths and patterns
3. Code change volume metrics (lines added/removed)
4. Directory-specific change patterns

This information would allow us to:
- Track specific types of changes (fixes, features, refactors)
- Identify hotspots in the codebase
- Monitor developer activity across different components
- Generate more granular DORA metrics

## Decision
We will enhance our commit data extraction and metric classification system to capture more detailed insights from commit metadata, with a focus on conventional commit formats and file path analysis.

## Changes Required

### 1. Dimension Extractor Enhancements

The `Domain::Extractors::DimensionExtractor` class will be extended with new methods:

```ruby
# New methods to add to DimensionExtractor

# Extract commit message components using conventional commit format
# @param commit [Hash] A single commit from the payload
# @return [Hash] Parsed components (type, scope, description)
def extract_conventional_commit_parts(commit)
  message = commit[:message] || ""
  
  # Match conventional commit format: type(scope): description
  if message.match?(/^(\w+)(\([\w-\/]+\))?!?: (.+)/)
    matches = message.match(/^(\w+)(\([\w-\/]+\))?!?: (.+)/)
    type = matches[1]
    scope = matches[2] ? matches[2].gsub(/[\(\)]/, '') : nil
    description = matches[3]
    breaking = message.include?("!")
    
    {
      type: type,
      scope: scope,
      description: description,
      breaking: breaking,
      conventional: true
    }
  else
    {
      description: message,
      conventional: false
    }
  end
end

# Extract modified files from a commit or push event
# @param event [Domain::Event] The GitHub event
# @return [Hash] File statistics by category
def extract_file_changes(event)
  # For individual commits
  if event.data[:commits]
    file_stats = { added: [], modified: [], removed: [] }
    
    event.data[:commits].each do |commit|
      file_stats[:added].concat(commit[:added] || [])
      file_stats[:modified].concat(commit[:modified] || [])
      file_stats[:removed].concat(commit[:removed] || [])
    end
    
    file_stats
  else
    # Handle other events that might contain file changes differently
    { added: [], modified: [], removed: [] }
  end
end

# Categorize file changes by directory and type
# @param files [Array<String>] List of file paths
# @return [Hash] Categorized file changes
def categorize_files(files)
  result = {
    directories: {},
    extensions: {}
  }
  
  files.each do |file|
    # Extract top-level directory
    dir = file.split('/').first
    result[:directories][dir] ||= 0
    result[:directories][dir] += 1
    
    # Extract file extension
    ext = File.extname(file).delete('.').downcase
    ext = 'no_extension' if ext.empty?
    result[:extensions][ext] ||= 0
    result[:extensions][ext] += 1
  end
  
  result
end

# Calculate code change volume from commits if available
# @param event [Domain::Event] The GitHub event
# @return [Hash] Code volume changes
def extract_code_volume(event)
  total_additions = 0
  total_deletions = 0
  
  if event.data[:commits]
    event.data[:commits].each do |commit|
      # Some GitHub webhook payloads include stats
      if commit[:stats]
        total_additions += commit[:stats][:additions].to_i
        total_deletions += commit[:stats][:deletions].to_i
      end
    end
  end
  
  {
    additions: total_additions,
    deletions: total_deletions
  }
end
```

### 2. GitHub Event Classifier Enhancements

The `Domain::Classifiers::GithubEventClassifier` class needs to be updated to use these new extractors and generate additional metrics:

```ruby
# Enhanced classify_push_event method in GithubEventClassifier

def classify_push_event(event)
  dimensions = extract_dimensions(event)
  metrics = []
  
  # Existing metrics
  metrics << create_metric(
    name: "github.push.total",
    value: 1,
    dimensions: dimensions
  )
  
  metrics << create_metric(
    name: "github.push.commits",
    value: @dimension_extractor ? @dimension_extractor.extract_commit_count(event) : 1,
    dimensions: dimensions
  )
  
  metrics << create_metric(
    name: "github.push.unique_authors",
    value: 1,
    dimensions: dimensions.merge(
      author: @dimension_extractor ? @dimension_extractor.extract_author(event) : "unknown"
    )
  )
  
  metrics << create_metric(
    name: "github.push.branch_activity",
    value: 1,
    dimensions: dimensions.merge(
      branch: @dimension_extractor ? @dimension_extractor.extract_branch(event) : "unknown"
    )
  )
  
  # New metrics for commit types (if using conventional commits)
  if @dimension_extractor && event.data[:commits]
    # Process each commit
    event.data[:commits].each do |commit|
      commit_parts = @dimension_extractor.extract_conventional_commit_parts(commit)
      
      # Only track conventional commits
      if commit_parts[:conventional]
        # Track by commit type (feat, fix, chore, etc.)
        metrics << create_metric(
          name: "github.push.commit_type",
          value: 1,
          dimensions: dimensions.merge(
            type: commit_parts[:type],
            scope: commit_parts[:scope] || "none"
          )
        )
        
        # Track breaking changes
        if commit_parts[:breaking]
          metrics << create_metric(
            name: "github.push.breaking_change",
            value: 1,
            dimensions: dimensions
          )
        end
      end
    end
    
    # File change metrics
    file_changes = @dimension_extractor.extract_file_changes(event)
    
    # Track overall file changes
    metrics << create_metric(
      name: "github.push.files_added",
      value: file_changes[:added].size,
      dimensions: dimensions
    )
    
    metrics << create_metric(
      name: "github.push.files_modified",
      value: file_changes[:modified].size,
      dimensions: dimensions
    )
    
    metrics << create_metric(
      name: "github.push.files_removed",
      value: file_changes[:removed].size,
      dimensions: dimensions
    )
    
    # Track directory-specific changes
    all_files = file_changes[:added] + file_changes[:modified] + file_changes[:removed]
    categorized_files = @dimension_extractor.categorize_files(all_files)
    
    categorized_files[:directories].each do |dir, count|
      metrics << create_metric(
        name: "github.push.directory_changes",
        value: count,
        dimensions: dimensions.merge(directory: dir)
      )
    end
    
    # Track file type changes
    categorized_files[:extensions].each do |ext, count|
      metrics << create_metric(
        name: "github.push.filetype_changes",
        value: count,
        dimensions: dimensions.merge(filetype: ext)
      )
    end
    
    # Track code volume if available
    code_volume = @dimension_extractor.extract_code_volume(event)
    if code_volume[:additions] > 0 || code_volume[:deletions] > 0
      metrics << create_metric(
        name: "github.push.code_additions",
        value: code_volume[:additions],
        dimensions: dimensions
      )
      
      metrics << create_metric(
        name: "github.push.code_deletions",
        value: code_volume[:deletions],
        dimensions: dimensions
      )
    end
  end
  
  { metrics: metrics }
end
```

### 3. RSpec Tests

We'll need corresponding tests for the new functionality:

1. Tests for `extract_conventional_commit_parts` with various message formats
2. Tests for file change extraction and categorization
3. Tests for the enhanced metrics generation in push events

## Benefits

1. **Enhanced Project Analysis**: Understand what types of changes are happening (fixes vs features)
2. **Codebase Health Monitoring**: Identify hotspots with frequent changes that might need refactoring
3. **Developer Workflow Insights**: See patterns in how code changes flow through the system
4. **DORA Metrics Accuracy**: Better data for calculating change failure rates and other metrics
5. **Repository Structure Insights**: Understand which components change most frequently

## Implementation Plan

1. Extend the `DimensionExtractor` with the new methods for commit parsing
2. Update the `GithubEventClassifier` to generate the additional metrics
3. Add comprehensive tests for the new functionality
4. Update the documentation to reflect the new metrics
5. Consider dashboarding extensions to visualize the new metrics

## Stakeholders

- Engineering teams using the metrics platform
- Engineering leadership tracking DORA metrics
- Development teams tracking specific areas of the codebase

## Status

Proposed

## Consequences

### Positive

- More detailed insights into code changes
- Better understanding of commit patterns
- Enhanced ability to track DORA metrics
- Ability to detect conventional commit usage

### Negative

- Increased complexity in the metrics system
- More data to store and process
- Potential for metric explosions if many directories/file types are tracked 