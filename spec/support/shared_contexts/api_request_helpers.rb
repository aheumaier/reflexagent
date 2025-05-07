# frozen_string_literal: true

# Shared context for API request specs
RSpec.shared_context "api_request_helpers" do
  include ActionDispatch::IntegrationTest::Behavior
  include Rails.application.routes.url_helpers
  include ActionDispatch::TestProcess::FixtureFile

  def post_json(path, params: nil, headers: {})
    default_headers = { "Content-Type" => "application/json" }
    post path, params: params.is_a?(String) ? params : params.to_json,
               headers: default_headers.merge(headers)
  end

  def get_json(path, params: nil, headers: {})
    default_headers = { "Accept" => "application/json" }
    get path, params: params, headers: default_headers.merge(headers)
  end

  def json_response
    JSON.parse(response.body)
  end
end
