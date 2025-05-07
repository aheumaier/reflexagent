RSpec.shared_examples "a storage port implementation" do
  it { is_expected.to respond_to(:save_event).with(1).argument }
  it { is_expected.to respond_to(:find_event).with(1).argument }
  it { is_expected.to respond_to(:save_metric).with(1).argument }
  it { is_expected.to respond_to(:find_metric).with(1).argument }
  it { is_expected.to respond_to(:save_alert).with(1).argument }
  it { is_expected.to respond_to(:find_alert).with(1).argument }

  context "with an event" do
    include_context "event examples"

    it "saves and retrieves events" do
      saved_event = subject.save_event(event)
      retrieved_event = subject.find_event(saved_event.id)

      expect(retrieved_event.id).to eq(saved_event.id)
      expect(retrieved_event.name).to eq(event.name)
      expect(retrieved_event.source).to eq(event.source)
    end
  end
end

RSpec.shared_examples "a cache port implementation" do
  it { is_expected.to respond_to(:cache_metric).with(1).argument }
  it { is_expected.to respond_to(:get_cached_metric).with(1..2).arguments }
  it { is_expected.to respond_to(:clear_metric_cache).with(0..1).arguments }

  context "with a metric" do
    include_context "metric examples"

    it "caches and retrieves metrics" do
      subject.cache_metric(metric)
      retrieved_value = subject.get_cached_metric(metric.name, metric.dimensions)

      expect(retrieved_value).not_to be_nil
      expect(retrieved_value).to eq(metric.value)
    end

    it "clears the cache" do
      subject.cache_metric(metric)
      subject.clear_metric_cache

      expect(subject.get_cached_metric(metric.name, metric.dimensions)).to be_nil
    end
  end
end

RSpec.shared_examples "a notification port implementation" do
  it { is_expected.to respond_to(:send_alert).with(1).argument }
  it { is_expected.to respond_to(:send_message).with(2).arguments }

  context "with an alert" do
    include_context "alert examples"

    it "can send an alert" do
      expect(subject.send_alert(alert)).to be_truthy
    end
  end

  context "with a message" do
    it "can send a message to a channel" do
      expect(subject.send_message("test-channel", "Test message")).to be_truthy
    end
  end
end

RSpec.shared_examples "a queue port implementation" do
  it { is_expected.to respond_to(:enqueue_metric_calculation).with(1).argument }
  it { is_expected.to respond_to(:enqueue_anomaly_detection).with(1).argument }

  context "with an event" do
    include_context "event examples"

    it "can enqueue an event for metric calculation" do
      expect(subject.enqueue_metric_calculation(event)).to be_truthy
    end
  end

  context "with a metric" do
    include_context "metric examples"

    it "can enqueue a metric for anomaly detection" do
      expect(subject.enqueue_anomaly_detection(metric)).to be_truthy
    end
  end
end

RSpec.shared_examples "a dashboard port implementation" do
  it { is_expected.to respond_to(:update_dashboard_with_metric).with(1).argument }
  it { is_expected.to respond_to(:update_dashboard_with_alert).with(1).argument }

  context "with a metric" do
    include_context "metric examples"

    it "can update the dashboard with a metric" do
      expect(subject.update_dashboard_with_metric(metric)).to be_truthy
    end
  end

  context "with an alert" do
    include_context "alert examples"

    it "can update the dashboard with an alert" do
      expect(subject.update_dashboard_with_alert(alert)).to be_truthy
    end
  end
end
