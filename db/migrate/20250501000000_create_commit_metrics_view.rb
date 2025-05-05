class CreateCommitMetricsView < ActiveRecord::Migration[7.1]
  def up
    # Create a view that makes it easier to query commit-related metrics
    execute <<-SQL
      CREATE OR REPLACE VIEW commit_metrics AS
      SELECT
        id,
        name,
        value,
        source,
        dimensions->>'repository' as repository,
        dimensions->>'organization' as organization,
        dimensions->>'branch' as branch,
        dimensions->>'author' as author,
        dimensions->>'type' as commit_type,
        dimensions->>'scope' as commit_scope,
        dimensions->>'directory' as directory,
        dimensions->>'filetype' as filetype,

        -- Convert to boolean
        CASE WHEN dimensions->>'breaking' = 'true' THEN true ELSE false END as breaking_change,

        -- Only for code volume metrics
        CASE WHEN name = 'github.push.code_additions' THEN value ELSE 0 END as lines_added,
        CASE WHEN name = 'github.push.code_deletions' THEN value ELSE 0 END as lines_deleted,

        -- Only for file metrics
        CASE WHEN name = 'github.push.files_added' THEN value ELSE 0 END as files_added,
        CASE WHEN name = 'github.push.files_modified' THEN value ELSE 0 END as files_modified,
        CASE WHEN name = 'github.push.files_removed' THEN value ELSE 0 END as files_removed,

        recorded_at
      FROM
        metrics
      WHERE
        name LIKE 'github.push.%' OR
        name LIKE 'github.pull_request.%'
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS commit_metrics"
  end
end
