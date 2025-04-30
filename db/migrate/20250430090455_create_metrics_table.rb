class CreateMetricsTable < ActiveRecord::Migration[7.1]
  def up
    # Create the main metrics table with partitioning
    execute <<-SQL
      CREATE TABLE metrics (
        id          BIGSERIAL PRIMARY KEY,
        name        TEXT       NOT NULL,
        value       DOUBLE PRECISION NOT NULL,
        source      TEXT       NOT NULL,
        dimensions  JSONB,
        recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
      ) PARTITION BY RANGE (recorded_at);
    SQL

    # Create initial monthly partitions (current month and next month)
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month

    execute <<-SQL
      CREATE TABLE metrics_#{current_month.strftime('%Y_%m')} PARTITION OF metrics
        FOR VALUES FROM ('#{current_month}') TO ('#{next_month}');

      CREATE TABLE metrics_#{next_month.strftime('%Y_%m')} PARTITION OF metrics
        FOR VALUES FROM ('#{next_month}') TO ('#{next_month.next_month}');
    SQL

    # Create indexes for efficient querying
    execute <<-SQL
      CREATE INDEX metrics_name_idx ON metrics (name);
      CREATE INDEX metrics_recorded_at_idx ON metrics (recorded_at);
      CREATE INDEX metrics_name_recorded_at_idx ON metrics (name, recorded_at);
    SQL
  end

  def down
    # Drop the partitions first
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month

    execute <<-SQL
      DROP TABLE IF EXISTS metrics_#{current_month.strftime('%Y_%m')};
      DROP TABLE IF EXISTS metrics_#{next_month.strftime('%Y_%m')};
    SQL

    # Drop the main table
    execute <<-SQL
      DROP TABLE IF EXISTS metrics;
    SQL
  end
end
