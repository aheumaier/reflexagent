require 'rails_helper'
require_relative '../../../app/core/domain/actuator'
require_relative '../../../app/core/use_cases/actuator_controller'

RSpec.describe Core::UseCases::ActuatorController do
  let(:ci_pipeline_actuator) do
    instance_double(
      "Core::Domain::Actuator",
      name: "ci_pipeline",
      properties: { provider: "Jenkins", type: "hvac", location: "main-repo" },
      respond_to?: true
    )
  end

  let(:team_notification_actuator) do
    instance_double(
      "Core::Domain::Actuator",
      name: "team_notifications",
      properties: { platform: "Slack", type: "light", location: "dev-team" },
      respond_to?: true
    )
  end

  let(:issue_tracker_actuator) do
    instance_double(
      "Core::Domain::Actuator",
      name: "issue_tracker",
      properties: { tool: "Jira", type: "door", location: "sprint-board" },
      respond_to?: true
    )
  end

  subject(:controller) { described_class.new }

  before do
    # Setup mock behavior for actuators
    allow(ci_pipeline_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
    allow(team_notification_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
    allow(issue_tracker_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)

    # Add generic fallback for send method first
    allow(ci_pipeline_actuator).to receive(:send).and_return(nil)
    allow(team_notification_actuator).to receive(:send).and_return(nil)
    allow(issue_tracker_actuator).to receive(:send).and_return(nil)

    # Then override with specific property returns
    allow(ci_pipeline_actuator).to receive(:send).with(:properties).and_return({ provider: "Jenkins", type: "hvac", location: "main-repo" })
    allow(ci_pipeline_actuator).to receive(:send).with(:provider).and_return("Jenkins")
    allow(ci_pipeline_actuator).to receive(:send).with(:type).and_return("hvac")
    allow(ci_pipeline_actuator).to receive(:send).with(:location).and_return("main-repo")

    allow(team_notification_actuator).to receive(:send).with(:properties).and_return({ platform: "Slack", type: "light", location: "dev-team" })
    allow(team_notification_actuator).to receive(:send).with(:platform).and_return("Slack")
    allow(team_notification_actuator).to receive(:send).with(:type).and_return("light")
    allow(team_notification_actuator).to receive(:send).with(:location).and_return("dev-team")

    allow(issue_tracker_actuator).to receive(:send).with(:properties).and_return({ tool: "Jira", type: "door", location: "sprint-board" })
    allow(issue_tracker_actuator).to receive(:send).with(:tool).and_return("Jira")
    allow(issue_tracker_actuator).to receive(:send).with(:type).and_return("door")
    allow(issue_tracker_actuator).to receive(:send).with(:location).and_return("sprint-board")
  end

  describe "#initialize" do
    it "creates an empty actuators hash" do
      expect(controller.actuators).to eq({})
    end
  end

  describe "#register" do
    context "with a valid actuator" do
      it "adds the actuator to the internal collection" do
        controller.register(ci_pipeline_actuator)
        expect(controller.actuators["ci_pipeline"]).to eq(ci_pipeline_actuator)
      end

      it "returns true on successful registration" do
        expect(controller.register(ci_pipeline_actuator)).to eq(true)
      end
    end

    context "with an already registered actuator name" do
      before { controller.register(ci_pipeline_actuator) }

      it "raises an ArgumentError" do
        duplicate_actuator = instance_double("Core::Domain::Actuator", name: "ci_pipeline")
        allow(duplicate_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)

        expect {
          controller.register(duplicate_actuator)
        }.to raise_error(ArgumentError, "An actuator with name 'ci_pipeline' is already registered")
      end
    end

    context "with an invalid actuator" do
      it "raises an ArgumentError" do
        invalid_object = double("NotAnActuator")
        allow(invalid_object).to receive(:is_a?).with(Core::Domain::Actuator).and_return(false)

        expect {
          controller.register(invalid_object)
        }.to raise_error(ArgumentError, "Only actuators can be registered")
      end
    end
  end

  describe "#unregister" do
    before do
      controller.register(ci_pipeline_actuator)
      controller.register(team_notification_actuator)
    end

    context "with an existing actuator name" do
      it "removes the actuator from the internal collection" do
        controller.unregister("ci_pipeline")
        expect(controller.actuators).not_to have_key("ci_pipeline")
      end

      it "returns true on successful unregistration" do
        expect(controller.unregister("ci_pipeline")).to eq(true)
      end
    end

    context "with a non-existent actuator name" do
      it "returns false" do
        expect(controller.unregister("non_existent")).to eq(false)
      end

      it "does not modify the actuators collection" do
        expect {
          controller.unregister("non_existent")
        }.not_to change { controller.actuators.size }
      end
    end
  end

  describe "#find_actuators" do
    before do
      controller.register(ci_pipeline_actuator)
      controller.register(team_notification_actuator)
      controller.register(issue_tracker_actuator)
    end

    context "with no criteria" do
      it "returns all registered actuators" do
        expect(controller.find_actuators).to contain_exactly(ci_pipeline_actuator, team_notification_actuator, issue_tracker_actuator)
      end
    end

    context "with name criteria" do
      it "returns actuators matching the name" do
        expect(controller.find_actuators(name: "ci_pipeline")).to contain_exactly(ci_pipeline_actuator)
      end
    end

    context "with property criteria" do
      it "returns actuators matching the property" do
        expect(controller.find_actuators(provider: "Jenkins")).to contain_exactly(ci_pipeline_actuator)
      end
    end

    context "with attribute criteria" do
      it "returns actuators matching the attribute" do
        expect(controller.find_actuators(location: "main-repo")).to contain_exactly(ci_pipeline_actuator)
      end
    end

    context "with multiple criteria" do
      it "returns actuators matching all criteria" do
        expect(
          controller.find_actuators(location: "main-repo", type: "hvac")
        ).to contain_exactly(ci_pipeline_actuator)
      end
    end

    context "with criteria that match no actuators" do
      it "returns an empty array" do
        expect(controller.find_actuators(location: "non-existent")).to be_empty
      end
    end
  end

  describe "#execute_action" do
    before do
      controller.register(ci_pipeline_actuator)
    end

    context "with a valid actuator and action" do
      it "executes the action on the actuator" do
        action_params = { action: "start_build", branch: "main" }
        result = { success: true, message: "Build started on main branch" }

        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_return(result)

        expect(controller.execute_action("ci_pipeline", action_params)).to eq(
          result.merge(actuator_name: "ci_pipeline")
        )
      end
    end

    context "with a non-existent actuator" do
      it "returns an error result" do
        expect(controller.execute_action("non_existent", { action: "start_build" })).to eq(
          {
            success: false,
            error: "Actuator 'non_existent' not found"
          }
        )
      end
    end

    context "when actuator raises ArgumentError" do
      it "catches the error and returns an error result" do
        action_params = { action: "start_build" }

        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_raise(
          ArgumentError, "Missing branch parameter"
        )

        expect(controller.execute_action("ci_pipeline", action_params)).to eq(
          {
            success: false,
            actuator_name: "ci_pipeline",
            error: "Missing branch parameter"
          }
        )
      end
    end

    context "when actuator raises other errors" do
      it "catches the error and returns an error result" do
        action_params = { action: "start_build" }

        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_raise(
          RuntimeError, "Failed to connect to CI server"
        )

        expect(controller.execute_action("ci_pipeline", action_params)).to eq(
          {
            success: false,
            actuator_name: "ci_pipeline",
            error: "Execution error: Failed to connect to CI server"
          }
        )
      end
    end
  end

  describe "#execute_group_action" do
    before do
      controller.register(ci_pipeline_actuator)
      controller.register(team_notification_actuator)
    end

    context "with criteria matching multiple actuators" do
      it "executes the action on all matching actuators" do
        # Setup the mocks for the actuator type check
        allow(ci_pipeline_actuator).to receive(:properties).and_return({ provider: "Jenkins", environment: "staging" })
        allow(ci_pipeline_actuator).to receive(:send).with(:properties).and_return({ provider: "Jenkins", environment: "staging" })
        allow(ci_pipeline_actuator).to receive(:send).with(:environment).and_return("staging")

        allow(team_notification_actuator).to receive(:properties).and_return({ platform: "Slack", environment: "staging" })
        allow(team_notification_actuator).to receive(:send).with(:properties).and_return({ platform: "Slack", environment: "staging" })
        allow(team_notification_actuator).to receive(:send).with(:environment).and_return("staging")

        # Setup expectations for the execute method
        action_params = { message: "Deploying to staging" }
        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI pipeline notified" }
        )
        expect(team_notification_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Slack notified" }
        )

        # Call the method under test
        results = controller.execute_group_action({ environment: "staging" }, action_params)

        # Verify the results
        expect(results[:success]).to eq(true)
        expect(results[:count]).to eq(2)
        expect(results[:results].size).to eq(2)
        expect(results[:results]).to include(
          { success: true, message: "CI pipeline notified", actuator_name: "ci_pipeline" },
          { success: true, message: "Slack notified", actuator_name: "team_notifications" }
        )
      end
    end

    context "with criteria matching no actuators" do
      it "returns an error result" do
        results = controller.execute_group_action({ environment: "production" }, { action: "deploy" })
        expect(results[:success]).to eq(false)
        expect(results[:error]).to eq("No actuators match the criteria")
      end
    end

    context "when some actuators fail" do
      it "returns mixed results" do
        # Setup the mocks for the actuator type check
        allow(ci_pipeline_actuator).to receive(:properties).and_return({ provider: "Jenkins", environment: "staging" })
        allow(ci_pipeline_actuator).to receive(:send).with(:properties).and_return({ provider: "Jenkins", environment: "staging" })
        allow(ci_pipeline_actuator).to receive(:send).with(:environment).and_return("staging")

        allow(team_notification_actuator).to receive(:properties).and_return({ platform: "Slack", environment: "staging" })
        allow(team_notification_actuator).to receive(:send).with(:properties).and_return({ platform: "Slack", environment: "staging" })
        allow(team_notification_actuator).to receive(:send).with(:environment).and_return("staging")

        # Setup expectations for the execute method
        action_params = { message: "Deploying to staging" }
        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI pipeline notified" }
        )
        expect(team_notification_actuator).to receive(:execute).with(action_params).and_raise(
          RuntimeError, "Failed to connect to Slack"
        )

        # Call the method under test
        results = controller.execute_group_action({ environment: "staging" }, action_params)

        # Verify the results
        expect(results[:success]).to eq(false)
        expect(results[:count]).to eq(2)
        expect(results[:results].size).to eq(2)
        expect(results[:results]).to include(
          { success: true, message: "CI pipeline notified", actuator_name: "ci_pipeline" },
          { success: false, error: "Failed to connect to Slack", actuator_name: "team_notifications" }
        )
      end
    end
  end

  describe "#execute_type_action" do
    let(:second_hvac) do
      instance_double(
        "Core::Domain::Actuator",
        name: "deploy_pipeline",
        properties: { provider: "Jenkins", type: "hvac", location: "deploy-repo" },
        respond_to?: true
      )
    end

    before do
      controller.register(ci_pipeline_actuator)
      controller.register(team_notification_actuator)

      # Setup mock behavior for type check
      allow(second_hvac).to receive(:is_a?).and_return(false)  # Default first
      allow(second_hvac).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)  # Override for Actuator
      allow(second_hvac).to receive(:send).with(:properties).and_return({ provider: "Jenkins", type: "hvac", location: "deploy-repo" })
      allow(second_hvac).to receive(:send).with(:type).and_return("hvac")
      allow(second_hvac).to receive(:send).with(:location).and_return("deploy-repo")

      # Register the second_hvac actuator
      controller.register(second_hvac)
    end

    context "with actuators of the specified type" do
      it "executes the action on all actuators of the type" do
        action_params = { action: "start_build", branch: "main" }

        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI build started" }
        )
        expect(second_hvac).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Deploy build started" }
        )

        results = controller.execute_type_action("hvac", action_params)

        expect(results[:success]).to eq(true)
        expect(results[:count]).to eq(2)
        expect(results[:results].size).to eq(2)
        expect(results[:results]).to include(
          { success: true, message: "CI build started", actuator_name: "ci_pipeline" },
          { success: true, message: "Deploy build started", actuator_name: "deploy_pipeline" }
        )
      end
    end

    context "with no actuators of the specified type" do
      it "returns an error result" do
        results = controller.execute_type_action("unknown_type", { action: "some_action" })
        expect(results[:success]).to eq(false)
        expect(results[:error]).to eq("No actuators of type 'unknown_type' found")
      end
    end

    context "when some actuators fail" do
      it "returns mixed results" do
        action_params = { action: "start_build", branch: "main" }

        expect(ci_pipeline_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI build started" }
        )
        expect(second_hvac).to receive(:execute).with(action_params).and_raise(
          RuntimeError, "Failed to connect to CI server"
        )

        results = controller.execute_type_action("hvac", action_params)

        expect(results[:success]).to eq(false)
        expect(results[:count]).to eq(2)
        expect(results[:results].size).to eq(2)
        expect(results[:results]).to include(
          { success: true, message: "CI build started", actuator_name: "ci_pipeline" },
          { success: false, error: "Failed to connect to CI server", actuator_name: "deploy_pipeline" }
        )
      end
    end
  end
end
