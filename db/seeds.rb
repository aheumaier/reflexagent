# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Seed data for DORA metrics - Deployment Frequency

# Clean up existing metrics for testing
# puts "Cleaning up existing deployment metrics..."
# DomainMetric.where(name: "ci.deploy.completed").delete_all

# # Create a Domain::Metric class if it doesn't exist
# module Domain
#   class Metric
#     attr_accessor :id, :name, :value, :source, :dimensions, :timestamp

#     def initialize(name:, value:, id: nil, source: "seed", dimensions: {}, timestamp: Time.now)
#       @id = id
#       @name = name
#       @value = value
#       @source = source
#       @dimensions = dimensions
#       @timestamp = timestamp
#     end

#     def with_id(new_id)
#       @id = new_id
#       self
#     end
#   end
# end

# # Set up metrics repository
# repo = Repositories::MetricRepository.new

# # Generate deployment data for the last 30 days
# puts "Creating deployment metrics..."
# (0..30).each do |days_ago|
#   # Skip some days to simulate non-daily deployments
#   next if [3, 5, 10, 15, 20, 25].include?(days_ago)

#   # Create random number of deployments for each day (1-3)
#   deployments_count = rand(1..3)

#   deployments_count.times do |i|
#     # Create a deployment metric
#     timestamp = days_ago.days.ago + rand(8..17).hours + rand(0..59).minutes

#     metric = Domain::Metric.new(
#       name: "ci.deploy.completed",
#       value: 1,
#       source: "deployment-service",
#       dimensions: {
#         environment: ["production", "staging"].sample,
#         service: ["api", "web", "auth", "payments"].sample,
#         deploy_id: "deploy-#{timestamp.to_i}-#{i}",
#         status: "success"
#       },
#       timestamp: timestamp
#     )

#     repo.save_metric(metric)
#   end
# end

# puts "Created deployment metrics for DORA calculations"
