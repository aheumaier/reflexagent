require 'rails_helper'

RSpec.describe ApplicationMailer do
  before do
    # Stub mail delivery methods to prevent actual email sending
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now).and_return(true)
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later).and_return(true)

    # Set default environment variables
    ENV['MAILER_FROM'] = 'notifications@example.com'
    ENV['ALERT_RECIPIENTS'] = 'admin@example.com'
    ENV['CHANNEL_RECIPIENTS'] = 'admin@example.com'
  end

  describe '#alert_notification' do
    let(:severity) { :critical }
    let(:message) { 'CPU usage is very high' }
    let(:timestamp) { Time.current }
    let(:details) { { metric_value: 98.5, threshold: 90, source: 'web-01' } }
    let(:mail) do
      ApplicationMailer.alert_notification(
        severity: severity,
        message: message,
        timestamp: timestamp,
        details: details
      )
    end

    it 'renders the subject with severity and message' do
      expect(mail.subject).to eq("[CRITICAL] Alert: CPU usage is very high")
    end

    it 'sends to the notification recipients' do
      expect(mail.to).to eq(['admin@example.com'])
    end

    it 'sends from the configured address' do
      expect(mail.from).to eq(['notifications@example.com'])
    end

    it 'is configured correctly' do
      expect(mail.body.encoded).not_to be_empty
    end
  end

  describe '#general_notification' do
    let(:channel) { 'monitoring' }
    let(:message) { 'System deployment completed successfully' }
    let(:mail) do
      ApplicationMailer.general_notification(
        channel: channel,
        message: message
      )
    end

    it 'renders the subject with the channel' do
      expect(mail.subject).to eq("[MONITORING] Notification")
    end

    it 'sends to the channel recipients' do
      expect(mail.to).to eq(['admin@example.com'])
    end

    it 'sends from the configured address' do
      expect(mail.from).to eq(['notifications@example.com'])
    end

    it 'is configured correctly' do
      expect(mail.body.encoded).not_to be_empty
    end
  end
end
