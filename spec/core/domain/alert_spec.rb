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
end
