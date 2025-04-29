require 'securerandom'

# spec/support/factory_bot.rb
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end

# Register additional factory methods for domain objects
# This ensures we're using the right initializers
FactoryBot.define do
  # Custom strategies for domain entities if needed
end
