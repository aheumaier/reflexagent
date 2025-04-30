namespace :metrics do
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
    retention_months = ENV.fetch('METRICS_RETENTION_MONTHS', 12).to_i
    cutoff_date = Date.today.beginning_of_month - retention_months.months

    puts "Cleaning up metrics older than #{cutoff_date}"

    # Find partitions older than the cutoff date
    ActiveRecord::Base.connection.execute(
      "SELECT tablename FROM pg_catalog.pg_tables " \
      "WHERE tablename LIKE 'metrics_%' AND tablename != 'metrics'"
    ).each do |row|
      table_name = row["tablename"]

      # Extract date from the partition name (metrics_YYYY_MM)
      if table_name =~ /metrics_(\d{4})_(\d{2})/
        year, month = $1.to_i, $2.to_i
        partition_date = Date.new(year, month, 1)

        if partition_date < cutoff_date
          puts "Dropping old partition #{table_name} for #{partition_date}"
          ActiveRecord::Base.connection.execute("DROP TABLE #{table_name};")
        end
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
