require 'rails_helper'

RSpec.describe HexagonalHelpers::MockPorts::MockStoragePort do
  subject { described_class.new }

  it_behaves_like "a storage port implementation"

  describe '#save_event' do
    include_context "event examples"

    it "adds the event to saved_events" do
      subject.save_event(event)
      expect(subject.saved_events).to include(event)
    end

    it "assigns an id if one is not provided" do
      result = subject.save_event(event_without_id)
      expect(result.id).not_to be_nil
    end
  end
end

RSpec.describe HexagonalHelpers::MockPorts::MockCachePort do
  subject { described_class.new }

  it_behaves_like "a cache port implementation"
end

RSpec.describe HexagonalHelpers::MockPorts::MockNotificationPort do
  subject { described_class.new }

  it_behaves_like "a notification port implementation"

  describe '#send_alert' do
    include_context "alert examples"

    it "adds the alert to sent_alerts" do
      subject.send_alert(alert)
      expect(subject.sent_alerts).to include(alert)
    end
  end
end

RSpec.describe HexagonalHelpers::MockPorts::MockQueuePort do
  subject { described_class.new }

  it_behaves_like "a queue port implementation"

  describe '#enqueue_metric_calculation' do
    include_context "event examples"

    it "adds the event to enqueued_events" do
      subject.enqueue_metric_calculation(event)
      expect(subject.enqueued_events).to include(event)
    end
  end
end
