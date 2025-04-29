RSpec.shared_context "with mock storage port" do
  let(:mock_storage_port) { HexagonalHelpers::MockPorts::MockStoragePort.new }

  before do
    DependencyContainer.register(:storage_port, mock_storage_port)
  end
end

RSpec.shared_context "with mock cache port" do
  let(:mock_cache_port) { HexagonalHelpers::MockPorts::MockCachePort.new }

  before do
    DependencyContainer.register(:cache_port, mock_cache_port)
  end
end

RSpec.shared_context "with mock notification port" do
  let(:mock_notification_port) { HexagonalHelpers::MockPorts::MockNotificationPort.new }

  before do
    DependencyContainer.register(:notification_port, mock_notification_port)
  end
end

RSpec.shared_context "with mock queue port" do
  let(:mock_queue_port) { HexagonalHelpers::MockPorts::MockQueuePort.new }

  before do
    DependencyContainer.register(:queue_port, mock_queue_port)
  end
end

RSpec.shared_context "with all mock ports" do
  include_context "with mock storage port"
  include_context "with mock cache port"
  include_context "with mock notification port"
  include_context "with mock queue port"
end
