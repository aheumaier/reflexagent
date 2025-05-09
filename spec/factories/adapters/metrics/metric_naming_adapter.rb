# frozen_string_literal: true

FactoryBot.define do
  factory :metric_naming_adapter, class: "Adapters::Metrics::MetricNamingAdapter" do
    # No attributes needed as the adapter is stateless
    initialize_with { new }
  end
end
