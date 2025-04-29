FactoryBot.define do
  factory :event, class: 'Core::Domain::Event' do
    id { SecureRandom.uuid }
    name { 'user.login' }
    source { 'web_api' }
    timestamp { Time.current }
    data { { user_id: 123, ip_address: '192.168.1.1' } }

    initialize_with do
      new(
        id: id,
        name: name,
        source: source,
        timestamp: timestamp,
        data: data
      )
    end

    trait :login do
      name { 'user.login' }
      data { { user_id: 123, ip_address: '192.168.1.1' } }
    end

    trait :logout do
      name { 'user.logout' }
      data { { user_id: 123, session_duration: 3600 } }
    end

    trait :purchase do
      name { 'order.purchase' }
      data { { user_id: 123, order_id: 456, amount: 99.99 } }
    end
  end
end
