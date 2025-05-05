# app/ports/logger_port.rb
module Ports
  module LoggerPort
    def debug(message)
      raise NotImplementedError, "Implement in adapter"
    end

    def info(message)
      raise NotImplementedError, "Implement in adapter"
    end

    def warn(message)
      raise NotImplementedError, "Implement in adapter"
    end

    def error(message)
      raise NotImplementedError, "Implement in adapter"
    end
  end
end
