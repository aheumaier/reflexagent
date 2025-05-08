# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Classifiers::GithubEventClassifier do
  let(:dimension_extractor) { Domain::Extractors::DimensionExtractor.new }
  let(:classifier) { described_class.new(dimension_extractor) }

  describe "#classify_workflow_job_event" do
    context "with a successful workflow job event (E2E Tests)" do
      let(:event) do
        # Load workflow_job for E2E test run from JSON file
        workflow_job_data = JSON.parse(
          File.read("test/data/github/workflow_job_success.json")
        ).with_indifferent_access

        FactoryBot.build(
          :event,
          name: "github.workflow_job.completed",
          source: "github",
          data: workflow_job_data
        )
      end

      it "returns the expected basic metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)

        # We expect enhanced metrics (at least 4)
        expect(result[:metrics].size).to be >= 4

        # Check for workflow_job.completed metric
        job_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.completed" }
        expect(job_metric).to be_present
        expect(job_metric[:value]).to eq(1)
        expect(job_metric[:dimensions][:repository]).to eq("aheumaier/reflexagent")
        expect(job_metric[:dimensions][:organization]).to eq("aheumaier")
        expect(job_metric[:dimensions][:job_name]).to eq("Run E2E Tests")
        expect(job_metric[:dimensions][:workflow_name]).to eq("Test & Deploy to Render")
        expect(job_metric[:dimensions][:branch]).to eq("main")

        # Check for conclusion metric
        conclusion_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.conclusion.success" }
        expect(conclusion_metric).to be_present
        expect(conclusion_metric[:dimensions][:job_name]).to eq("Run E2E Tests")

        # Check for duration metric
        duration_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.duration" }
        expect(duration_metric).to be_present
        expect(duration_metric[:value]).to eq(60) # 60 seconds duration

        # Check for specific test metrics since this is an E2E test job
        test_duration_metric = result[:metrics].find { |m| m[:name] == "github.ci.test.duration" }
        expect(test_duration_metric).to be_present
        expect(test_duration_metric[:dimensions][:workflow_name]).to eq("Test & Deploy to Render")

        # Check for test success metric
        test_success_metric = result[:metrics].find { |m| m[:name] == "github.ci.test.success" }
        expect(test_success_metric).to be_present
        expect(test_success_metric[:value]).to eq(1) # 1 for success
      end

      it "tracks step-level metrics for important steps" do
        result = classifier.classify(event)

        # Look for the actual test run step
        test_step_metric = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.test.duration" &&
            m[:dimensions][:step_name] == "Run E2E tests"
        end

        expect(test_step_metric).to be_present
        expect(test_step_metric[:value]).to eq(26) # 26 seconds duration

        # Check for step success metric
        test_step_success = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.test.success" &&
            m[:dimensions][:step_name] == "Run E2E tests"
        end

        expect(test_step_success).to be_present
        expect(test_step_success[:value]).to eq(1) # 1 for success
      end
    end

    context "with a failed workflow job event (Test job)" do
      let(:event) do
        # Load workflow_job for failed test from JSON file
        workflow_job_data = JSON.parse(
          File.read("test/data/github/workflow_job_failure.json")
        ).with_indifferent_access

        FactoryBot.build(
          :event,
          name: "github.workflow_job.completed",
          source: "github",
          data: workflow_job_data
        )
      end

      it "returns the expected test failure metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)

        # Check for basic metrics
        job_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.completed" }
        expect(job_metric).to be_present
        expect(job_metric[:dimensions][:job_name]).to eq("Run Tests Before Deploy")

        # Check for conclusion metric
        conclusion_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.conclusion.failure" }
        expect(conclusion_metric).to be_present

        # Check for duration metric
        duration_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.duration" }
        expect(duration_metric).to be_present
        expect(duration_metric[:value]).to eq(41) # 41 seconds duration (from started_at to completed_at)

        # Check for specific test metrics since this is a test job
        test_duration_metric = result[:metrics].find { |m| m[:name] == "github.ci.test.duration" }
        expect(test_duration_metric).to be_present

        # Check for test failure metric
        test_failed_metric = result[:metrics].find { |m| m[:name] == "github.ci.test.success" }
        expect(test_failed_metric).to be_present
        expect(test_failed_metric[:value]).to eq(0) # 0 for failure
      end

      it "tracks step-level metrics for test steps" do
        result = classifier.classify(event)

        # Look for the actual test run step
        test_step_metric = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.test.duration" &&
            m[:dimensions][:step_name] == "Run all tests"
        end

        expect(test_step_metric).to be_present

        # Check for step failure metric
        test_step_failure = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.test.failure" &&
            m[:dimensions][:step_name] == "Run all tests"
        end

        expect(test_step_failure).to be_present
        expect(test_step_failure[:value]).to eq(1) # 1 for failure
      end
    end

    context "with a failed deployment job event" do
      let(:event) do
        # Create a deployment job payload based on workflow_job_success.json but with failure status
        deploy_job_data = JSON.parse(
          File.read("test/data/github/workflow_job_success.json")
        ).with_indifferent_access

        # Modify the data to represent a deployment job
        deploy_job_data[:workflow_job][:name] = "Deploy to Render"
        deploy_job_data[:workflow_job][:conclusion] = "failure"
        deploy_job_data[:workflow_job][:started_at] = "2025-05-07T13:06:00Z"
        deploy_job_data[:workflow_job][:completed_at] = "2025-05-07T13:06:30Z"

        # Create deployment steps
        deploy_job_data[:workflow_job][:steps] = [
          {
            name: "Set up job",
            status: "completed",
            conclusion: "success",
            number: 1,
            started_at: "2025-05-07T13:06:00Z",
            completed_at: "2025-05-07T13:06:02Z"
          },
          {
            name: "Run actions/checkout@v3",
            status: "completed",
            conclusion: "success",
            number: 2,
            started_at: "2025-05-07T13:06:02Z",
            completed_at: "2025-05-07T13:06:05Z"
          },
          {
            name: "Deploy to Render",
            status: "completed",
            conclusion: "failure",
            number: 3,
            started_at: "2025-05-07T13:06:05Z",
            completed_at: "2025-05-07T13:06:25Z"
          },
          {
            name: "Post Run actions/checkout@v3",
            status: "completed",
            conclusion: "success",
            number: 4,
            started_at: "2025-05-07T13:06:25Z",
            completed_at: "2025-05-07T13:06:28Z"
          },
          {
            name: "Complete job",
            status: "completed",
            conclusion: "success",
            number: 5,
            started_at: "2025-05-07T13:06:28Z",
            completed_at: "2025-05-07T13:06:30Z"
          }
        ]

        FactoryBot.build(
          :event,
          name: "github.workflow_job.completed",
          source: "github",
          data: deploy_job_data
        )
      end

      it "returns the expected deployment failure metrics" do
        result = classifier.classify(event)

        expect(result).to be_a(Hash)
        expect(result[:metrics]).to be_an(Array)

        # Check for basic metrics
        job_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.completed" }
        expect(job_metric).to be_present
        expect(job_metric[:dimensions][:job_name]).to eq("Deploy to Render")

        # Check for conclusion metric
        conclusion_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.conclusion.failure" }
        expect(conclusion_metric).to be_present

        # Check for duration metric
        duration_metric = result[:metrics].find { |m| m[:name] == "github.workflow_job.duration" }
        expect(duration_metric).to be_present
        expect(duration_metric[:value]).to eq(30) # 30 seconds duration

        # Check for specific deployment metrics
        deploy_duration_metric = result[:metrics].find { |m| m[:name] == "github.ci.deploy.duration" }
        expect(deploy_duration_metric).to be_present

        # Check for deployment failure metric
        deploy_failed_metric = result[:metrics].find { |m| m[:name] == "github.ci.deploy.failed" }
        expect(deploy_failed_metric).to be_present
        expect(deploy_failed_metric[:value]).to eq(1)

        # Ensure DORA deployment metrics are included
        dora_deploy_metric = result[:metrics].find { |m| m[:name] == "dora.deployment.attempt" }
        expect(dora_deploy_metric).to be_present
        expect(dora_deploy_metric[:value]).to eq(1)

        dora_deploy_failure = result[:metrics].find { |m| m[:name] == "dora.deployment.failure" }
        expect(dora_deploy_failure).to be_present
        expect(dora_deploy_failure[:value]).to eq(1)
      end

      it "tracks step-level metrics for deployment steps" do
        result = classifier.classify(event)

        # Look for the actual deploy step
        deploy_step_metric = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.deploy.duration" &&
            m[:dimensions][:step_name] == "Deploy to Render"
        end

        expect(deploy_step_metric).to be_present
        expect(deploy_step_metric[:value]).to eq(20) # 20 seconds duration

        # Check for step failure metric
        deploy_step_failure = result[:metrics].find do |m|
          m[:name] == "github.workflow_step.deploy.failure" &&
            m[:dimensions][:step_name] == "Deploy to Render"
        end

        expect(deploy_step_failure).to be_present
        expect(deploy_step_failure[:value]).to eq(1) # 1 for failure
      end
    end
  end
end
