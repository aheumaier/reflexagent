namespace :metrics do
  desc "Create a new partition for metrics table for the given month (format: YYYY-MM)"
  task :create_partition, [:month] => :environment do |_t, args|
    if args[:month].blank? || !args[:month].match?(/^\d{4}-\d{2}$/)
      puts "Please provide a month in the format YYYY-MM"
      puts "Example: rake metrics:create_partition[2025-06]"
      exit 1
    end

    begin
      # Parse the month and calculate the range
      year, month = args[:month].split("-").map(&:to_i)
      start_date = Date.new(year, month, 1)
      end_date = start_date.next_month

      partition_name = "metrics_#{start_date.strftime('%Y_%m')}"

      # Check if the partition already exists
      exists = ActiveRecord::Base.connection.execute(
        "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = '#{partition_name}')"
      ).first["exists"]

      if exists
        puts "Partition #{partition_name} already exists."
        exit 0
      end

      # Create the partition
      ActiveRecord::Base.connection.execute(
        "CREATE TABLE #{partition_name} PARTITION OF metrics " \
        "FOR VALUES FROM ('#{start_date}') TO ('#{end_date}');"
      )

      # Add indexes to the new partition (same as in the migration)
      ActiveRecord::Base.connection.execute(<<~SQL)
        CREATE INDEX idx_#{partition_name}_dimensions ON #{partition_name} USING GIN (dimensions);
        CREATE INDEX idx_#{partition_name}_dimensions_path_ops ON #{partition_name} USING GIN (dimensions jsonb_path_ops);
        CREATE INDEX idx_#{partition_name}_source ON #{partition_name} (source);
        CREATE INDEX idx_#{partition_name}_name_source_recorded_at ON #{partition_name} (name, source, recorded_at);
        CREATE INDEX idx_#{partition_name}_name ON #{partition_name} (name);
      SQL

      puts "Created partition #{partition_name} for range #{start_date} to #{end_date}"
      puts "Added indexes to partition #{partition_name}"
    rescue StandardError => e
      puts "Error creating partition: #{e.message}"
      exit 1
    end
  end

  desc "Check and create next month's partition if it doesn't exist"
  task ensure_next_partition: :environment do
    # Calculate next month
    next_month = Date.today.next_month.beginning_of_month
    partition_name = "metrics_#{next_month.strftime('%Y_%m')}"

    # Check if the partition already exists
    exists = ActiveRecord::Base.connection.execute(
      "SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = '#{partition_name}')"
    ).first["exists"]

    unless exists
      # If it doesn't exist, create it with the create_partition task
      Rake::Task["metrics:create_partition"].invoke(next_month.strftime("%Y-%m"))
    end
  end

  desc "Analyze metrics table to update PostgreSQL statistics"
  task analyze: :environment do
    ActiveRecord::Base.connection.execute("ANALYZE metrics")
    puts "Analyzed metrics table to update statistics"
  end

  desc "Create partition for the metrics table for the next month"
  task create_next_partition: :environment do
    # Calculate the start of the month after next
    current_month = Date.today.beginning_of_month
    next_month = current_month.next_month
    month_after_next = next_month.next_month

    # Format the partition table name
    partition_name = "metrics_#{month_after_next.strftime('%Y_%m')}"

    # Check if the partition already exists
    result = ActiveRecord::Base.connection.execute(
      "SELECT to_regclass('#{partition_name}');"
    ).first["to_regclass"]

    if result.nil?
      puts "Creating partition #{partition_name} for range #{month_after_next} to #{month_after_next.next_month}"

      # Create the partition
      ActiveRecord::Base.connection.execute(
        "CREATE TABLE #{partition_name} PARTITION OF metrics " \
        "FOR VALUES FROM ('#{month_after_next}') TO ('#{month_after_next.next_month}');"
      )

      puts "Partition #{partition_name} created successfully"
    else
      puts "Partition #{partition_name} already exists, skipping"
    end
  end

  desc "Clean up old metric data (older than retention period)"
  task cleanup: :environment do
    # Default retention period is 12 months
    retention_months = ENV.fetch("METRICS_RETENTION_MONTHS", 12).to_i
    cutoff_date = Date.today.beginning_of_month - retention_months.months

    puts "Cleaning up metrics older than #{cutoff_date}"

    # Find partitions older than the cutoff date
    ActiveRecord::Base.connection.execute(
      "SELECT tablename FROM pg_catalog.pg_tables " \
      "WHERE tablename LIKE 'metrics_%' AND tablename != 'metrics'"
    ).each do |row|
      table_name = row["tablename"]

      # Extract date from the partition name (metrics_YYYY_MM)
      next unless table_name =~ /metrics_(\d{4})_(\d{2})/

      year = Regexp.last_match(1).to_i
      month = Regexp.last_match(2).to_i
      partition_date = Date.new(year, month, 1)

      if partition_date < cutoff_date
        puts "Dropping old partition #{table_name} for #{partition_date}"
        ActiveRecord::Base.connection.execute("DROP TABLE #{table_name};")
      end
    end
  end

  desc "Schedule a monthly job to create new partitions and clean up old ones"
  task schedule_maintenance: :environment do
    # This would typically be run via a cron job on the 1st of each month
    Rake::Task["metrics:create_next_partition"].invoke
    Rake::Task["metrics:cleanup"].invoke
  end
end
