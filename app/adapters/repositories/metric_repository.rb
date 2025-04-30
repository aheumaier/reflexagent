module Adapters
  module Repositories
    class MetricRepository
      def initialize
        @metrics_cache = {}  # In-memory cache for tests
      end

      def save_metric(metric)
        # Create a database record
        domain_metric = DomainMetric.create!(
          name: metric.name,
          value: metric.value,
          source: metric.source,
          dimensions: metric.dimensions,
          recorded_at: metric.timestamp
        )

        # Update the domain metric with the database ID if needed
        if metric.id.nil?
          metric = metric.with_id(domain_metric.id.to_s)
        end

        # Store in memory cache for tests
        @metrics_cache[metric.id] = metric

        # Return the domain metric
        metric
      end

      def find_metric(id)
        # Try to find in memory cache first (for tests)
        return @metrics_cache[id] if @metrics_cache.key?(id)

        # Find in database
        domain_metric = DomainMetric.find_by(id: id)
        return nil unless domain_metric

        # Convert to domain model
        metric = Core::Domain::Metric.new(
          id: domain_metric.id.to_s,
          name: domain_metric.name,
          value: domain_metric.value,
          source: domain_metric.source,
          dimensions: domain_metric.dimensions || {},
          timestamp: domain_metric.recorded_at
        )

        # Cache for future lookups
        @metrics_cache[metric.id] = metric

        metric
      end

      def list_metrics(filters = {})
        # Start with a base query
        query = DomainMetric.all

        # Apply filters
        query = query.with_name(filters[:name]) if filters[:name]
        query = query.since(filters[:start_time]) if filters[:start_time]
        query = query.until(filters[:end_time]) if filters[:end_time]
        query = query.latest_first if filters[:latest_first]
        query = query.limit(filters[:limit]) if filters[:limit]

        # Convert to domain models
        query.map do |domain_metric|
          Core::Domain::Metric.new(
            id: domain_metric.id.to_s,
            name: domain_metric.name,
            value: domain_metric.value,
            source: domain_metric.source,
            dimensions: domain_metric.dimensions || {},
            timestamp: domain_metric.recorded_at
          )
        end
      end

      def get_average(name, start_time = nil, end_time = nil)
        DomainMetric.average_for(name, start_time, end_time)
      end

      def get_percentile(name, percentile, start_time = nil, end_time = nil)
        DomainMetric.percentile_for(name, percentile, start_time, end_time)
      end
    end
  end
end
