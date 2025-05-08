class RecreateMetricsAsPartitionedTable < ActiveRecord::Migration[7.1]
  def up
    # First, we need to create a backup of existing metrics data
    execute <<-SQL
      CREATE TABLE metrics_backup AS
      SELECT * FROM metrics;
    SQL

    # Now drop existing metrics table (and all indexes)
    execute <<-SQL
      DROP TABLE IF EXISTS metrics CASCADE;
    SQL

    # Also drop any existing partition tables
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month

    execute <<-SQL
      DROP TABLE IF EXISTS metrics_#{current_month.strftime('%Y_%m')} CASCADE;
      DROP TABLE IF EXISTS metrics_#{next_month.strftime('%Y_%m')} CASCADE;
    SQL

    # Create the main metrics table with partitioning
    execute <<-SQL
      CREATE TABLE metrics (
        id          BIGSERIAL,
        name        TEXT       NOT NULL,
        value       DOUBLE PRECISION NOT NULL,
        source      TEXT       NOT NULL,
        dimensions  JSONB,
        recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (id, recorded_at)
      ) PARTITION BY RANGE (recorded_at);
    SQL

    # Create initial monthly partitions (current month and next month)
    execute <<-SQL
      CREATE TABLE metrics_#{current_month.strftime('%Y_%m')} PARTITION OF metrics
        FOR VALUES FROM ('#{current_month}') TO ('#{next_month}');

      CREATE TABLE metrics_#{next_month.strftime('%Y_%m')} PARTITION OF metrics
        FOR VALUES FROM ('#{next_month}') TO ('#{next_month.next_month}');
    SQL

    # Create all the necessary indexes
    execute <<-SQL
      -- Single column indexes
      CREATE INDEX metrics_name_idx ON metrics (name);
      CREATE INDEX metrics_recorded_at_idx ON metrics (recorded_at);
      CREATE INDEX idx_metrics_source ON metrics (source);
      CREATE INDEX idx_metrics_name ON metrics (name);

      -- Composite indexes
      CREATE INDEX metrics_name_recorded_at_idx ON metrics (name, recorded_at);
      CREATE INDEX idx_metrics_name_source_recorded_at ON metrics (name, source, recorded_at);

      -- JSONB indexes
      CREATE INDEX idx_metrics_dimensions ON metrics USING GIN (dimensions);
      CREATE INDEX idx_metrics_dimensions_path_ops ON metrics USING GIN (dimensions jsonb_path_ops);
    SQL

    # Restore data from backup, but only if it's within our partition range
    execute <<-SQL
      INSERT INTO metrics (id, name, value, source, dimensions, recorded_at)
      SELECT id, name, value, source, dimensions, recorded_at
      FROM metrics_backup
      WHERE recorded_at >= '#{current_month}';
    SQL

    # Drop the backup table
    execute <<-SQL
      DROP TABLE metrics_backup;
    SQL
  end

  def down
    # This migration is not reversible because we can't guarantee
    # we can recover the exact state of the original table.
    raise ActiveRecord::IrreversibleMigration
  end
end
