module Ports
  module IngestionPort
    # @param raw_payload [String] the full JSON body
    # @param source [String] e.g. "github", "jira"
    # @return [Core::Domain::Event]
    def receive_event(raw_payload, source:)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def validate_webhook_signature(payload, signature)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
