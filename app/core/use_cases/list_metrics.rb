module UseCases
  class ListMetrics
    def initialize(storage_port:)
      @storage_port = storage_port
    end

    def call(filters = {})
      @storage_port.list_metrics(filters)
    end
  end
end
