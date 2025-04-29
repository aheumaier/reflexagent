require 'rails_helper'

RSpec.describe Core::Domain::Alert do
  include_context "alert examples"

  describe '#initialize' do
    context 'with all attributes' do
      subject { alert }

      it 'sets all attributes correctly' do
        expect(subject.id).to eq(alert_id)
        expect(subject.name).to eq(alert_name)
        expect(subject.severity).to eq(alert_severity)
        expect(subject.metric).to eq(metric)
        expect(subject.threshold).to eq(alert_threshold)
        expect(subject.timestamp).to eq(alert_timestamp)
        expect(subject.status).to eq(alert_status)
      end
    end

    context 'with required attributes only' do
      subject do
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: metric,
          threshold: alert_threshold
        )
      end

      it 'sets required attributes correctly' do
        expect(subject.id).to be_nil
        expect(subject.name).to eq(alert_name)
        expect(subject.severity).to eq(alert_severity)
        expect(subject.metric).to eq(metric)
        expect(subject.threshold).to eq(alert_threshold)
        expect(subject.timestamp).to be_a(Time)
        expect(subject.status).to eq(:active) # Default status
      end
    end

    context 'with valid severities' do
      described_class::SEVERITIES.each do |severity|
        context "with #{severity} severity" do
          subject do
            described_class.new(
              name: alert_name,
              severity: severity,
              metric: metric,
              threshold: alert_threshold
            )
          end

          it "accepts #{severity} as a valid severity" do
            expect(subject.severity).to eq(severity)
          end
        end
      end
    end

    context 'with valid statuses' do
      described_class::STATUSES.each do |status|
        context "with #{status} status" do
          subject do
            described_class.new(
              name: alert_name,
              severity: alert_severity,
              metric: metric,
              threshold: alert_threshold,
              status: status
            )
          end

          it "accepts #{status} as a valid status" do
            expect(subject.status).to eq(status)
          end
        end
      end
    end

    context 'with custom timestamp' do
      let(:custom_time) { Time.new(2023, 1, 1, 12, 0, 0) }

      subject do
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: metric,
          threshold: alert_threshold,
          timestamp: custom_time
        )
      end

      it 'uses the provided timestamp' do
        expect(subject.timestamp).to eq(custom_time)
      end
    end
  end

  describe 'constants' do
    it 'defines valid severities' do
      expect(described_class::SEVERITIES).to eq([:info, :warning, :critical].freeze)
    end

    it 'defines valid statuses' do
      expect(described_class::STATUSES).to eq([:active, :acknowledged, :resolved].freeze)
    end
  end

  describe 'attributes' do
    subject { alert }

    it 'has read-only attributes' do
      expect(subject).to respond_to(:id)
      expect(subject).to respond_to(:name)
      expect(subject).to respond_to(:severity)
      expect(subject).to respond_to(:metric)
      expect(subject).to respond_to(:threshold)
      expect(subject).to respond_to(:timestamp)
      expect(subject).to respond_to(:status)

      # Ensure attributes are read-only
      expect(subject).not_to respond_to(:id=)
      expect(subject).not_to respond_to(:name=)
      expect(subject).not_to respond_to(:severity=)
      expect(subject).not_to respond_to(:metric=)
      expect(subject).not_to respond_to(:threshold=)
      expect(subject).not_to respond_to(:timestamp=)
      expect(subject).not_to respond_to(:status=)
    end
  end

  describe 'factory' do
    subject { build(:alert) }

    it 'creates a valid alert' do
      expect(subject).to be_a(described_class)
      expect(subject.id).not_to be_nil
      expect(subject.name).not_to be_nil
      expect(subject.severity).to be_in(described_class::SEVERITIES)
      expect(subject.metric).to be_a(Core::Domain::Metric)
      expect(subject.threshold).not_to be_nil
      expect(subject.status).to be_in(described_class::STATUSES)
    end

    context 'with severity traits' do
      {
        warning: :warning,
        critical: :critical,
        info: :info
      }.each do |trait, expected_severity|
        context "with #{trait} trait" do
          subject { build(:alert, trait) }

          it "creates an alert with #{expected_severity} severity" do
            expect(subject.severity).to eq(expected_severity)
          end
        end
      end
    end

    context 'with status traits' do
      {
        active: :active,
        acknowledged: :acknowledged,
        resolved: :resolved
      }.each do |trait, expected_status|
        context "with #{trait} trait" do
          subject { build(:alert, trait) }

          it "creates an alert with #{expected_status} status" do
            expect(subject.status).to eq(expected_status)
          end
        end
      end
    end

    context 'with alert type traits' do
      context 'with high_response_time trait' do
        subject { build(:alert, :high_response_time) }

        it 'creates a response time alert' do
          expect(subject.name).to eq('High Response Time')
          expect(subject.metric.name).to eq('response_time')
          expect(subject.threshold).to eq(100)
        end
      end

      context 'with high_cpu_usage trait' do
        subject { build(:alert, :high_cpu_usage) }

        it 'creates a CPU usage alert' do
          expect(subject.name).to eq('High CPU Usage')
          expect(subject.metric.name).to eq('cpu_usage')
          expect(subject.threshold).to eq(80)
        end
      end
    end

    context 'with overrides' do
      subject do
        build(
          :alert,
          name: 'Custom Alert',
          severity: :info,
          threshold: 42,
          status: :acknowledged
        )
      end

      it 'allows overriding default values' do
        expect(subject.name).to eq('Custom Alert')
        expect(subject.severity).to eq(:info)
        expect(subject.threshold).to eq(42)
        expect(subject.status).to eq(:acknowledged)
      end
    end
  end

  describe '#message' do
    it 'returns the message for the alert' do
      expect(alert.message).to eq("#{alert_name} - #{metric.name} exceeded threshold of #{alert_threshold}")
    end
  end

  describe '#details' do
    it 'returns the details for the alert' do
      expected_details = {
        metric_name: metric.name,
        metric_value: metric.value,
        threshold: alert_threshold,
        source: metric.source,
        dimensions: metric.dimensions
      }
      expect(alert.details).to eq(expected_details)
    end
  end

  describe '#created_at' do
    it 'returns the created_at timestamp for the alert' do
      expect(alert.created_at).to eq(alert_timestamp)
    end
  end

  # Tests for the new validation methods
  describe '#valid?' do
    it 'returns true for a valid alert' do
      expect(alert).to be_valid
    end

    it 'raises an error for an alert with empty name' do
      expect {
        described_class.new(
          name: '',
          severity: alert_severity,
          metric: metric,
          threshold: alert_threshold
        )
      }.to raise_error(ArgumentError, "Name cannot be empty")
    end

    it 'raises an error for an alert with invalid severity' do
      expect {
        described_class.new(
          name: alert_name,
          severity: :invalid,
          metric: metric,
          threshold: alert_threshold
        )
      }.to raise_error(ArgumentError, /Severity must be one of/)
    end

    it 'raises an error for an alert with nil metric' do
      expect {
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: nil,
          threshold: alert_threshold
        )
      }.to raise_error(ArgumentError, "Metric cannot be nil")
    end

    it 'raises an error for an alert with wrong metric type' do
      expect {
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: "not a metric",
          threshold: alert_threshold
        )
      }.to raise_error(ArgumentError, "Metric must be a Core::Domain::Metric")
    end

    it 'raises an error for an alert with nil threshold' do
      expect {
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: metric,
          threshold: nil
        )
      }.to raise_error(ArgumentError, "Threshold cannot be nil")
    end

    it 'raises an error for an alert with invalid timestamp' do
      expect {
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: metric,
          threshold: alert_threshold,
          timestamp: 'invalid'
        )
      }.to raise_error(ArgumentError, "Timestamp must be a Time object")
    end

    it 'raises an error for an alert with invalid status' do
      expect {
        described_class.new(
          name: alert_name,
          severity: alert_severity,
          metric: metric,
          threshold: alert_threshold,
          status: :invalid
        )
      }.to raise_error(ArgumentError, /Status must be one of/)
    end
  end

  # Tests for equality methods
  describe '#==' do
    it 'returns true for identical alerts' do
      alert1 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      alert2 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      expect(alert1).to eq(alert2)
    end

    it 'returns false for alerts with different attributes' do
      alert1 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      alert2 = described_class.new(
        id: 'different-id',
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      expect(alert1).not_to eq(alert2)
    end

    it 'returns false for different types' do
      expect(alert).not_to eq('not an alert')
    end
  end

  describe '#hash' do
    it 'returns the same hash for identical alerts' do
      alert1 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      alert2 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      expect(alert1.hash).to eq(alert2.hash)
    end

    it 'returns different hash for different alerts' do
      alert1 = described_class.new(
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      alert2 = described_class.new(
        id: 'different-id',
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      )

      expect(alert1.hash).not_to eq(alert2.hash)
    end
  end

  # Tests for business logic methods
  describe '#acknowledge' do
    it 'changes the status to acknowledged' do
      active_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :active
      )

      acknowledged_alert = active_alert.acknowledge

      expect(acknowledged_alert.status).to eq(:acknowledged)
      expect(active_alert.status).to eq(:active) # Original should be unchanged
    end

    it 'returns the same alert if already acknowledged' do
      acknowledged_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :acknowledged
      )

      result = acknowledged_alert.acknowledge

      expect(result).to be(acknowledged_alert)
    end
  end

  describe '#resolve' do
    it 'changes the status to resolved' do
      active_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :active
      )

      resolved_alert = active_alert.resolve

      expect(resolved_alert.status).to eq(:resolved)
      expect(active_alert.status).to eq(:active) # Original should be unchanged
    end

    it 'returns the same alert if already resolved' do
      resolved_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :resolved
      )

      result = resolved_alert.resolve

      expect(result).to be(resolved_alert)
    end
  end

  describe '#escalate' do
    it 'changes the severity to a higher level' do
      warning_alert = described_class.new(
        name: alert_name,
        severity: :warning,
        metric: metric,
        threshold: alert_threshold
      )

      critical_alert = warning_alert.escalate(:critical)

      expect(critical_alert.severity).to eq(:critical)
      expect(warning_alert.severity).to eq(:warning) # Original should be unchanged
    end

    it 'returns the same alert if trying to escalate to a lower severity' do
      critical_alert = described_class.new(
        name: alert_name,
        severity: :critical,
        metric: metric,
        threshold: alert_threshold
      )

      result = critical_alert.escalate(:warning)

      expect(result).to be(critical_alert)
    end

    it 'returns the same alert if trying to escalate to an invalid severity' do
      warning_alert = described_class.new(
        name: alert_name,
        severity: :warning,
        metric: metric,
        threshold: alert_threshold
      )

      result = warning_alert.escalate(:invalid)

      expect(result).to be(warning_alert)
    end
  end

  describe 'status query methods' do
    it 'returns true for active? when status is active' do
      active_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :active
      )

      expect(active_alert.active?).to be true
      expect(active_alert.acknowledged?).to be false
      expect(active_alert.resolved?).to be false
    end

    it 'returns true for acknowledged? when status is acknowledged' do
      acknowledged_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :acknowledged
      )

      expect(acknowledged_alert.active?).to be false
      expect(acknowledged_alert.acknowledged?).to be true
      expect(acknowledged_alert.resolved?).to be false
    end

    it 'returns true for resolved? when status is resolved' do
      resolved_alert = described_class.new(
        name: alert_name,
        severity: alert_severity,
        metric: metric,
        threshold: alert_threshold,
        status: :resolved
      )

      expect(resolved_alert.active?).to be false
      expect(resolved_alert.acknowledged?).to be false
      expect(resolved_alert.resolved?).to be true
    end
  end

  describe 'severity query methods' do
    it 'returns true for info? when severity is info' do
      info_alert = described_class.new(
        name: alert_name,
        severity: :info,
        metric: metric,
        threshold: alert_threshold
      )

      expect(info_alert.info?).to be true
      expect(info_alert.warning?).to be false
      expect(info_alert.critical?).to be false
    end

    it 'returns true for warning? when severity is warning' do
      warning_alert = described_class.new(
        name: alert_name,
        severity: :warning,
        metric: metric,
        threshold: alert_threshold
      )

      expect(warning_alert.info?).to be false
      expect(warning_alert.warning?).to be true
      expect(warning_alert.critical?).to be false
    end

    it 'returns true for critical? when severity is critical' do
      critical_alert = described_class.new(
        name: alert_name,
        severity: :critical,
        metric: metric,
        threshold: alert_threshold
      )

      expect(critical_alert.info?).to be false
      expect(critical_alert.warning?).to be false
      expect(critical_alert.critical?).to be true
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the alert' do
      expected_hash = {
        id: alert_id,
        name: alert_name,
        severity: alert_severity,
        metric: metric.to_h,
        threshold: alert_threshold,
        timestamp: alert_timestamp,
        status: alert_status
      }

      expect(alert.to_h).to eq(expected_hash)
    end
  end

  describe '#with_id' do
    it 'creates a new alert with the specified id' do
      new_id = 'new-id'
      new_alert = alert.with_id(new_id)

      expect(new_alert).not_to eq(alert)
      expect(new_alert.id).to eq(new_id)
      expect(new_alert.name).to eq(alert.name)
      expect(new_alert.severity).to eq(alert.severity)
      expect(new_alert.metric).to eq(alert.metric)
      expect(new_alert.threshold).to eq(alert.threshold)
      expect(new_alert.timestamp).to eq(alert.timestamp)
      expect(new_alert.status).to eq(alert.status)
    end
  end
end
