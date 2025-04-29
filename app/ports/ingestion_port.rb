module Ports
  module IngestionPort
    def receive_event(payload)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end

    def validate_webhook_signature(payload, signature)
      raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
    end
  end
end
