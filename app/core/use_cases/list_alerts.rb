module UseCases
  class ListAlerts
    def initialize(storage_port:)
      @storage_port = storage_port
    end

    def call(filters = {})
      @storage_port.list_alerts(filters)
    end
  end
end
