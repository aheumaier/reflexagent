require "rails_helper"

RSpec.describe RawEventProcessorJob, type: :job do
  include ActiveJob::TestHelper

  let(:worker_id) { "test-worker-123" }
  let(:queue_adapter) { instance_double(Adapters::Queue::RedisQueueAdapter) }

  before do
    allow(DependencyContainer).to receive(:resolve).with(:queue_port).and_return(queue_adapter)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform" do
    before do
      # Default: process three batches of events, then empty batch
      allow(queue_adapter).to receive(:process_raw_event_batch)
        .with(worker_id)
        .and_return(10, 5, 2, 0, 0, 0, 0, 0)

      # Stop the job's loop after a few iterations to prevent test hanging
      original_method = RawEventProcessorJob.instance_method(:perform)
      allow_any_instance_of(RawEventProcessorJob).to receive(:perform) do |instance, job_worker_id|
        # Call the original method but use a reduced constant to exit the loop faster
        stub_const("RawEventProcessorJob::SLEEP_TIME", 0.01)
        counter = 0
        begin
          original_method.bind(instance).call(job_worker_id)
        rescue SystemExit
          # Do nothing, we're catching the exit
        end
      end
    end

    it "processes batches of events until getting empty batches" do
      expect(queue_adapter).to receive(:process_raw_event_batch).at_least(4).times
      expect(described_class).to receive(:perform_later).once

      perform_enqueued_jobs { described_class.perform_later(worker_id) }
    end

    it "logs the start and completion of processing" do
      expect(Rails.logger).to receive(:info).with(/RawEventProcessorJob started/).once
      expect(Rails.logger).to receive(:info).with(/RawEventProcessorJob completed/).once

      perform_enqueued_jobs { described_class.perform_later(worker_id) }
    end

    it "logs the number of processed events" do
      expect(Rails.logger).to receive(:info).with(/Processed 10 raw events/).once
      expect(Rails.logger).to receive(:info).with(/Processed 5 raw events/).once
      expect(Rails.logger).to receive(:info).with(/Processed 2 raw events/).once

      perform_enqueued_jobs { described_class.perform_later(worker_id) }
    end

    context "when consecutive empty batches reach the limit" do
      before do
        allow(queue_adapter).to receive(:process_raw_event_batch)
          .with(worker_id)
          .and_return(0, 0, 0, 0, 0)
      end

      it "re-enqueues itself and breaks the loop" do
        expect(described_class).to receive(:perform_later).with(worker_id).once

        perform_enqueued_jobs { described_class.perform_later(worker_id) }
      end

      it "logs taking a break" do
        expect(Rails.logger).to receive(:debug).with(/Taking a break after/).once

        perform_enqueued_jobs { described_class.perform_later(worker_id) }
      end
    end

    context "when processing errors occur" do
      let(:error) { StandardError.new("Test error") }

      before do
        call_count = 0
        allow(queue_adapter).to receive(:process_raw_event_batch) do |worker|
          call_count += 1
          case call_count
          when 1 then 5 # First call succeeds
          when 2 then raise error # Second call fails
          when 3 then 2 # Third call succeeds
          when 4 then raise error  # Fourth call fails
          when 5 then raise error  # Fifth call fails - reaches MAX_ERRORS
          else 0 # Empty batches
          end
        end
      end

      it "continues processing after errors" do
        expect(queue_adapter).to receive(:process_raw_event_batch).exactly(5).times

        perform_enqueued_jobs { described_class.perform_later(worker_id) }
      end

      it "logs errors" do
        expect(Rails.logger).to receive(:error).with(/Error processing raw events batch/).exactly(3).times

        perform_enqueued_jobs { described_class.perform_later(worker_id) }
      end

      it "stops processing after MAX_ERRORS consecutive errors" do
        expect(Rails.logger).to receive(:error).with(/Too many errors, stopping raw event processing/).once

        perform_enqueued_jobs { described_class.perform_later(worker_id) }
      end
    end
  end
end
