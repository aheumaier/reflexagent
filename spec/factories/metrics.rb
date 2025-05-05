FactoryBot.define do
  factory :metric, class: 'Domain::Metric' do
    id { SecureRandom.uuid }
    name { 'response_time' }
    value { 150.5 }
    timestamp { Time.current }
    source { 'api_gateway' }
    dimensions { { endpoint: '/users', method: 'GET' } }

    initialize_with do
      new(
        id: id,
        name: name,
        value: value,
        timestamp: timestamp,
        source: source,
        dimensions: dimensions
      )
    end

    trait :response_time do
      name { 'response_time' }
      value { 150.5 }
      dimensions { { endpoint: '/users', method: 'GET' } }
    end

    trait :cpu_usage do
      name { 'cpu_usage' }
      value { 75.2 }
      dimensions { { host: 'web-1', region: 'us-east-1' } }
    end

    trait :memory_usage do
      name { 'memory_usage' }
      value { 45.6 }
      dimensions { { host: 'web-1', region: 'us-east-1' } }
    end

    trait :request_count do
      name { 'request_count' }
      value { 250 }
      dimensions { { endpoint: '/api/v1/orders', method: 'POST' } }
    end
  end
end
