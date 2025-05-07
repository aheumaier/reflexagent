module ControllerHelpers
  # Helper method to mock webhook JSON handling
  def mock_webhook_json(controller, payload)
    allow(controller.request).to receive(:raw_post).and_return(payload)
    allow(JSON).to receive(:parse).and_call_original
    allow(JSON).to receive(:parse).with(payload).and_return(JSON.parse(payload))
  end

  # Helper to mock the params for JSON parsing in controller
  def mock_controller_params(source = "github")
    # Allow any string to be parsed as JSON in the test
    allow(JSON).to receive(:parse).with(any_args).and_call_original
    # Handle specific source parameter string
    allow(JSON).to receive(:parse).with("source=#{source}").and_raise(JSON::ParserError)
    # Handle responses from controller actions
    allow(JSON).to receive(:parse).with(any_args) do |arg|
      unless arg.is_a?(String) && arg.start_with?("{") && arg.end_with?("}")
        raise JSON::ParserError, "Invalid JSON: #{arg}"
      end

      JSON.parse(arg)
    end
  end
end

RSpec.configure do |config|
  config.include ControllerHelpers, type: :controller
end
