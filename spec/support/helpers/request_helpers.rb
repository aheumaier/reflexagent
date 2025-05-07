module RequestHelpers
  # Helper method to send a webhook with the correct format
  def post_webhook(source, payload = {})
    # Convert the payload to JSON if it's not already
    json_payload = payload.is_a?(String) ? payload : payload.to_json

    # Send the request with the right format for raw_post
    # We need to mock the raw post data because that's what the controller uses
    post "/api/v1/events?source=#{source}",
         headers: { "Content-Type" => "application/json" },
         as: :json,
         params: payload
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
