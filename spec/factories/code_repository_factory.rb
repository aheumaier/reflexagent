# frozen_string_literal: true

FactoryBot.define do
  factory :code_repository do
    sequence(:name) { |n| "org/repo-#{n}" }
    sequence(:url) { |n| "https://github.com/org/repo-#{n}" }
    provider { "github" }
    association :team
  end
end
