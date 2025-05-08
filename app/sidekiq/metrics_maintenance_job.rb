class MetricsMaintenanceJob
  include Sidekiq::Job

  # Set retry options for reliability
  sidekiq_options retry: 3, queue: "maintenance"

  # Run once per week (can be scheduled via sidekiq-scheduler)
  def perform
    Rails.logger.info("Starting metrics maintenance job")

    # Ensure we have next month's partition with proper indexes
    ensure_next_partition

    # Update PostgreSQL statistics for better query planning
    analyze_metrics_table

    Rails.logger.info("Completed metrics maintenance job")
  end

  private

  def ensure_next_partition
    Rails.logger.info("Ensuring next month's partition exists")

    # Calculate next month
    next_month = Date.today.next_month.beginning_of_month
    partition_name = "metrics_#{next_month.strftime('%Y_%m')}"

    # Check if the partition already exists
    exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = '#{partition_name}')"
    ).first["exists"]

    if exists
      Rails.logger.info("Partition #{partition_name} already exists")
    else
      Rails.logger.info("Creating new partition for #{next_month.strftime('%Y-%m')}")

      # Create the partition
      end_date = next_month.next_month
      ActiveRecord::Base.connection.execute(
        "CREATE TABLE #{partition_name} PARTITION OF metrics " \
        "FOR VALUES FROM ('#{next_month}') TO ('#{end_date}');"
      )

      # Add indexes to the new partition
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE INDEX idx_#{partition_name}_dimensions ON #{partition_name} USING GIN (dimensions);
        CREATE INDEX idx_#{partition_name}_dimensions_path_ops ON #{partition_name} USING GIN (dimensions jsonb_path_ops);
        CREATE INDEX idx_#{partition_name}_source ON #{partition_name} (source);
        CREATE INDEX idx_#{partition_name}_name_source_recorded_at ON #{partition_name} (name, source, recorded_at);
        CREATE INDEX idx_#{partition_name}_name ON #{partition_name} (name);
      SQL

      Rails.logger.info("Created partition #{partition_name} with all indexes")
    end
  end

  def analyze_metrics_table
    Rails.logger.info("Analyzing metrics table to update statistics")
    ActiveRecord::Base.connection.execute("ANALYZE metrics")
  end
end
