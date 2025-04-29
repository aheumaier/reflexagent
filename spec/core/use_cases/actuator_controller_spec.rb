require 'rails_helper'
require_relative '../../../app/core/domain/actuator'
require_relative '../../../app/core/use_cases/actuator_controller'

RSpec.describe Core::UseCases::ActuatorController do
  let(:hvac_actuator) do
    instance_double(
      "Core::Domain::HvacActuator",
      name: "ci_pipeline",
      device_id: "pipeline-123",
      location: "main-repo",
      properties: { provider: "Jenkins" },
      respond_to?: true
    )
  end

  let(:light_actuator) do
    instance_double(
      "Core::Domain::LightActuator",
      name: "team_notifications",
      location: "dev-team",
      properties: { platform: "Slack" },
      respond_to?: true
    )
  end

  let(:door_actuator) do
    instance_double(
      "Core::Domain::DoorActuator",
      name: "issue_tracker",
      door_id: "project-123",
      location: "sprint-board",
      properties: { tool: "Jira" },
      respond_to?: true
    )
  end

  subject(:controller) { described_class.new }

  before do
    # Setup is_a? checks for all actuators - add default first
    allow(hvac_actuator).to receive(:is_a?).and_return(false)
    allow(light_actuator).to receive(:is_a?).and_return(false)
    allow(door_actuator).to receive(:is_a?).and_return(false)

    # Then override with specific matches
    allow(hvac_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
    allow(light_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
    allow(door_actuator).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)

    allow(hvac_actuator).to receive(:is_a?).with(Core::Domain::HvacActuator).and_return(true)
    allow(light_actuator).to receive(:is_a?).with(Core::Domain::LightActuator).and_return(true)
    allow(door_actuator).to receive(:is_a?).with(Core::Domain::DoorActuator).and_return(true)

    # Add generic fallback for send method first
    allow(hvac_actuator).to receive(:send).and_return(nil)
    allow(light_actuator).to receive(:send).and_return(nil)
    allow(door_actuator).to receive(:send).and_return(nil)

    # Then override with specific attribute and property returns
    allow(hvac_actuator).to receive(:send).with(:device_id).and_return("pipeline-123")
    allow(hvac_actuator).to receive(:send).with(:location).and_return("main-repo")
    allow(hvac_actuator).to receive(:send).with(:properties).and_return({ provider: "Jenkins" })
    allow(hvac_actuator).to receive(:send).with(:provider).and_return("Jenkins")

    allow(light_actuator).to receive(:send).with(:location).and_return("dev-team")
    allow(light_actuator).to receive(:send).with(:properties).and_return({ platform: "Slack" })
    allow(light_actuator).to receive(:send).with(:platform).and_return("Slack")

    allow(door_actuator).to receive(:send).with(:door_id).and_return("project-123")
    allow(door_actuator).to receive(:send).with(:location).and_return("sprint-board")
    allow(door_actuator).to receive(:send).with(:properties).and_return({ tool: "Jira" })
    allow(door_actuator).to receive(:send).with(:tool).and_return("Jira")
  end

  describe "#initialize" do
    it "creates an empty actuators hash" do
      expect(controller.actuators).to eq({})
    end
  end

  describe "#register" do
    context "with a valid actuator" do
      it "adds the actuator to the internal collection" do
        controller.register(hvac_actuator)
        expect(controller.actuators["ci_pipeline"]).to eq(hvac_actuator)
      end

      it "returns true on successful registration" do
        expect(controller.register(hvac_actuator)).to eq(true)
      end
    end

    context "with an already registered actuator name" do
      before { controller.register(hvac_actuator) }

      it "raises an ArgumentError" do
        duplicate_actuator = instance_double("Core::Domain::HvacActuator", name: "ci_pipeline")
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
      controller.register(hvac_actuator)
      controller.register(light_actuator)
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
      controller.register(hvac_actuator)
      controller.register(light_actuator)
      controller.register(door_actuator)
    end

    context "with no criteria" do
      it "returns all registered actuators" do
        expect(controller.find_actuators).to contain_exactly(hvac_actuator, light_actuator, door_actuator)
      end
    end

    context "with name criteria" do
      it "returns actuators matching the name" do
        expect(controller.find_actuators(name: "ci_pipeline")).to contain_exactly(hvac_actuator)
      end
    end

    context "with property criteria" do
      it "returns actuators matching the property" do
        expect(controller.find_actuators(provider: "Jenkins")).to contain_exactly(hvac_actuator)
      end
    end

    context "with attribute criteria" do
      it "returns actuators matching the attribute" do
        expect(controller.find_actuators(location: "main-repo")).to contain_exactly(hvac_actuator)
      end
    end

    context "with multiple criteria" do
      it "returns actuators matching all criteria" do
        # Override properties for this specific test
        allow(hvac_actuator).to receive(:properties).and_return({ provider: "Jenkins", type: "build" })
        allow(hvac_actuator).to receive(:send).with(:properties).and_return({ provider: "Jenkins", type: "build" })
        allow(hvac_actuator).to receive(:send).with(:type).and_return("build")

        allow(light_actuator).to receive(:properties).and_return({ platform: "Slack", type: "build" })
        allow(light_actuator).to receive(:send).with(:properties).and_return({ platform: "Slack", type: "build" })
        allow(light_actuator).to receive(:send).with(:type).and_return("build")

        expect(
          controller.find_actuators(location: "main-repo", type: "build")
        ).to contain_exactly(hvac_actuator)
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
      controller.register(hvac_actuator)
    end

    context "with a valid actuator and action" do
      it "executes the action on the actuator" do
        action_params = { action: "start_build", branch: "main" }
        result = { success: true, message: "Build started on main branch" }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_return(result)

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

        expect(hvac_actuator).to receive(:execute).with(action_params).and_raise(
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
        action_params = { action: "start_build", branch: "main" }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_raise(
          RuntimeError, "CI server connection failed"
        )

        expect(controller.execute_action("ci_pipeline", action_params)).to eq(
          {
            success: false,
            actuator_name: "ci_pipeline",
            error: "Execution error: CI server connection failed"
          }
        )
      end
    end
  end

  describe "#execute_group_action" do
    before do
      controller.register(hvac_actuator)
      controller.register(light_actuator)
      controller.register(door_actuator)
    end

    context "with criteria matching multiple actuators" do
      it "executes the action on all matching actuators" do
        # Setup both actuators to have the same repository/location
        allow(hvac_actuator).to receive(:send).with(:location).and_return("shared-repo")
        allow(light_actuator).to receive(:send).with(:location).and_return("shared-repo")

        # Properly update location attribute for consistency
        allow(hvac_actuator).to receive(:location).and_return("shared-repo")
        allow(light_actuator).to receive(:location).and_return("shared-repo")

        action_params = { action: "update_status", status: "failed" }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI status updated to failed" }
        )

        expect(light_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Notification sent for failed status" }
        )

        results = controller.execute_group_action({ location: "shared-repo" }, action_params)

        expect(results).to contain_exactly(
          { success: true, message: "CI status updated to failed", actuator_name: "ci_pipeline" },
          { success: true, message: "Notification sent for failed status", actuator_name: "team_notifications" }
        )
      end
    end

    context "with criteria matching no actuators" do
      it "returns an error result" do
        results = controller.execute_group_action({ location: "non-existent" }, { action: "update_status" })

        expect(results).to eq([
          {
            success: false,
            error: "No actuators found matching criteria: {:location=>\"non-existent\"}"
          }
        ])
      end
    end

    context "when some actuators fail" do
      it "returns mixed results" do
        # Set both to the same repository/location
        allow(hvac_actuator).to receive(:send).with(:location).and_return("shared-repo")
        allow(light_actuator).to receive(:send).with(:location).and_return("shared-repo")

        # Properly update location attribute for consistency
        allow(hvac_actuator).to receive(:location).and_return("shared-repo")
        allow(light_actuator).to receive(:location).and_return("shared-repo")

        action_params = { action: "update_status" }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "CI status updated" }
        )

        expect(light_actuator).to receive(:execute).with(action_params).and_raise(
          ArgumentError, "Missing status parameter"
        )

        results = controller.execute_group_action({ location: "shared-repo" }, action_params)

        expect(results).to contain_exactly(
          { success: true, message: "CI status updated", actuator_name: "ci_pipeline" },
          {
            success: false,
            actuator_name: "team_notifications",
            error: "Missing status parameter"
          }
        )
      end
    end
  end

  describe "#execute_type_action" do
    before do
      controller.register(hvac_actuator)
      controller.register(light_actuator)
      controller.register(door_actuator)
    end

    context "with actuators of the specified type" do
      let(:second_hvac) do
        instance_double(
          "Core::Domain::HvacActuator",
          name: "feature_pipeline",
          device_id: "pipeline-456",
          location: "feature-repo",
          properties: {}
        )
      end

      before do
        allow(second_hvac).to receive(:is_a?).and_return(false)
        allow(second_hvac).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
        allow(second_hvac).to receive(:is_a?).with(Core::Domain::HvacActuator).and_return(true)
        allow(second_hvac).to receive(:send).and_return(nil)
        controller.register(second_hvac)
      end

      it "executes the action on all actuators of the type" do
        action_params = { action: "refresh_status", force: true }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Main pipeline status refreshed" }
        )

        expect(second_hvac).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Feature pipeline status refreshed" }
        )

        results = controller.execute_type_action(Core::Domain::HvacActuator, action_params)

        expect(results).to contain_exactly(
          { success: true, message: "Main pipeline status refreshed", actuator_name: "ci_pipeline" },
          { success: true, message: "Feature pipeline status refreshed", actuator_name: "feature_pipeline" }
        )
      end
    end

    context "with no actuators of the specified type" do
      it "returns an error result" do
        dummy_type = Class.new

        results = controller.execute_type_action(dummy_type, { action: "execute" })

        expect(results).to eq([
          {
            success: false,
            error: "No actuators found of type: #{dummy_type}"
          }
        ])
      end
    end

    context "when some actuators fail" do
      let(:second_hvac) do
        instance_double(
          "Core::Domain::HvacActuator",
          name: "feature_pipeline",
          properties: {}
        )
      end

      before do
        allow(second_hvac).to receive(:is_a?).and_return(false)
        allow(second_hvac).to receive(:is_a?).with(Core::Domain::Actuator).and_return(true)
        allow(second_hvac).to receive(:is_a?).with(Core::Domain::HvacActuator).and_return(true)
        allow(second_hvac).to receive(:send).and_return(nil)
        controller.register(second_hvac)
      end

      it "returns mixed results" do
        action_params = { action: "trigger_deploy", environment: "staging" }

        expect(hvac_actuator).to receive(:execute).with(action_params).and_return(
          { success: true, message: "Main pipeline deployed to staging" }
        )

        expect(second_hvac).to receive(:execute).with(action_params).and_raise(
          RuntimeError, "Deployment permission denied"
        )

        results = controller.execute_type_action(Core::Domain::HvacActuator, action_params)

        expect(results).to contain_exactly(
          { success: true, message: "Main pipeline deployed to staging", actuator_name: "ci_pipeline" },
          {
            success: false,
            actuator_name: "feature_pipeline",
            error: "Execution error: Deployment permission denied"
          }
        )
      end
    end
  end
end
