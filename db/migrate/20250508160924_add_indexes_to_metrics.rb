class AddIndexesToMetrics < ActiveRecord::Migration[7.1]
  def up
    # Add a GIN index on the dimensions JSONB column to improve queries using the @> operator
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_metrics_dimensions ON metrics USING GIN (dimensions);
    SQL

    # Add a more efficient GIN index specifically for @> operator
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_metrics_dimensions_path_ops ON metrics USING GIN (dimensions jsonb_path_ops);
    SQL

    # Add an index on source column for filtering by source
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_metrics_source ON metrics (source);
    SQL

    # Add a composite index for common query patterns that filter by name, source, and time range
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_metrics_name_source_recorded_at ON metrics (name, source, recorded_at);
    SQL

    # Add a separate index on name to be used together with dimensions GIN index
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_metrics_name ON metrics (name);
    SQL

    # Add indexes to current partition tables (adjust names as needed)
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month

    # Check if the current month partition exists
    current_partition_exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = 'metrics_#{current_month.strftime('%Y_%m')}')"
    ).first["exists"]

    if current_partition_exists
      # Add the same indexes to current month partition
      execute <<-SQL
        CREATE INDEX IF NOT EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_dimensions
          ON metrics_#{current_month.strftime('%Y_%m')} USING GIN (dimensions);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_dimensions_path_ops
          ON metrics_#{current_month.strftime('%Y_%m')} USING GIN (dimensions jsonb_path_ops);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_source
          ON metrics_#{current_month.strftime('%Y_%m')} (source);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_name_source_recorded_at
          ON metrics_#{current_month.strftime('%Y_%m')} (name, source, recorded_at);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_name
          ON metrics_#{current_month.strftime('%Y_%m')} (name);
      SQL
    end

    # Check if the next month partition exists
    next_partition_exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = 'metrics_#{next_month.strftime('%Y_%m')}')"
    ).first["exists"]

    if next_partition_exists
      # Add the same indexes to next month partition
      execute <<-SQL
        CREATE INDEX IF NOT EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_dimensions
          ON metrics_#{next_month.strftime('%Y_%m')} USING GIN (dimensions);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_dimensions_path_ops
          ON metrics_#{next_month.strftime('%Y_%m')} USING GIN (dimensions jsonb_path_ops);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_source
          ON metrics_#{next_month.strftime('%Y_%m')} (source);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_name_source_recorded_at
          ON metrics_#{next_month.strftime('%Y_%m')} (name, source, recorded_at);

        CREATE INDEX IF NOT EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_name
          ON metrics_#{next_month.strftime('%Y_%m')} (name);
      SQL
    end
  end

  def down
    # Drop indexes from the main table
    execute <<-SQL
      DROP INDEX IF EXISTS idx_metrics_dimensions;
      DROP INDEX IF EXISTS idx_metrics_dimensions_path_ops;
      DROP INDEX IF EXISTS idx_metrics_source;
      DROP INDEX IF EXISTS idx_metrics_name_source_recorded_at;
      DROP INDEX IF EXISTS idx_metrics_name;
    SQL

    # Drop indexes from partition tables
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month

    # Check if the current month partition exists
    current_partition_exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = 'metrics_#{current_month.strftime('%Y_%m')}')"
    ).first["exists"]

    if current_partition_exists
      # Current month partition
      execute <<-SQL
        DROP INDEX IF EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_dimensions;
        DROP INDEX IF EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_dimensions_path_ops;
        DROP INDEX IF EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_source;
        DROP INDEX IF EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_name_source_recorded_at;
        DROP INDEX IF EXISTS idx_metrics_#{current_month.strftime('%Y_%m')}_name;
      SQL
    end

    # Check if the next month partition exists
    next_partition_exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = 'metrics_#{next_month.strftime('%Y_%m')}')"
    ).first["exists"]

    if next_partition_exists
      # Next month partition
      execute <<-SQL
        DROP INDEX IF EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_dimensions;
        DROP INDEX IF EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_dimensions_path_ops;
        DROP INDEX IF EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_source;
        DROP INDEX IF EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_name_source_recorded_at;
        DROP INDEX IF EXISTS idx_metrics_#{next_month.strftime('%Y_%m')}_name;
      SQL
    end
  end
end
