FactoryBot.define do
  factory :alert, class: 'Domain::Alert' do
    id { SecureRandom.uuid }
    name { 'High Response Time' }
    severity { :warning }
    association :metric, factory: :metric, strategy: :build
    threshold { 100 }
    timestamp { Time.current }
    status { :active }

    initialize_with do
      new(
        id: id,
        name: name,
        severity: severity,
        metric: metric,
        threshold: threshold,
        timestamp: timestamp,
        status: status
      )
    end

    trait :warning do
      severity { :warning }
    end

    trait :critical do
      severity { :critical }
      name { 'Critical Response Time' }
    end

    trait :info do
      severity { :info }
      name { 'Elevated Response Time' }
    end

    trait :active do
      status { :active }
    end

    trait :acknowledged do
      status { :acknowledged }
    end

    trait :resolved do
      status { :resolved }
    end

    trait :high_response_time do
      name { 'High Response Time' }
      severity { :warning }
      association :metric, factory: [:metric, :response_time], strategy: :build
      threshold { 100 }
    end

    trait :high_cpu_usage do
      name { 'High CPU Usage' }
      severity { :critical }
      association :metric, factory: [:metric, :cpu_usage], strategy: :build
      threshold { 80 }
    end

    trait :high_memory_usage do
      name { 'High Memory Usage' }
      severity { :warning }
      association :metric, factory: [:metric, :memory_usage], strategy: :build
      threshold { 75 }
    end
  end
end
