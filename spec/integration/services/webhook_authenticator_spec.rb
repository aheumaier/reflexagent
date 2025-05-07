require "rails_helper"

RSpec.describe WebhookAuthenticator do
  describe ".valid?" do
    context "with valid tokens" do
      before do
        # Set up environment variables for testing
        allow(ENV).to receive(:[]).and_return(nil) # Default to nil for any environment variable
        allow(ENV).to receive(:[]).with("GITHUB_WEBHOOK_SECRET").and_return("github_secret")
        allow(ENV).to receive(:[]).with("JIRA_WEBHOOK_SECRET").and_return("jira_secret")
        allow(ENV).to receive(:[]).with("DEFAULT_WEBHOOK_SECRET").and_return("default_secret")
      end

      it "returns true for valid GitHub token" do
        result = WebhookAuthenticator.valid?("github_secret", "github")
        expect(result).to be true
      end

      it "returns true for valid Jira token" do
        result = WebhookAuthenticator.valid?("jira_secret", "jira")
        expect(result).to be true
      end

      it "returns true for valid token for custom source" do
        result = WebhookAuthenticator.valid?("default_secret", "custom")
        expect(result).to be true
      end
    end

    context "with invalid tokens" do
      before do
        allow(ENV).to receive(:[]).with("GITHUB_WEBHOOK_SECRET").and_return("github_secret")
      end

      it "returns false for invalid token" do
        expect(WebhookAuthenticator.valid?("wrong_token", "github")).to be false
      end

      it "returns false for nil token" do
        expect(WebhookAuthenticator.valid?(nil, "github")).to be false
      end

      it "returns false for blank token" do
        expect(WebhookAuthenticator.valid?("", "github")).to be false
      end
    end

    context "with invalid sources" do
      it "returns false for nil source" do
        expect(WebhookAuthenticator.valid?("token", nil)).to be false
      end

      it "returns false for blank source" do
        expect(WebhookAuthenticator.valid?("token", "")).to be false
      end
    end

    context "when falling back to demo token" do
      before do
        # Ensure no ENV variables or credentials are set
        allow(ENV).to receive(:[]).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      end

      it "uses demo token when no configuration is available" do
        expect(WebhookAuthenticator.valid?("demo_secret_token", "github")).to be true
      end
    end
  end

  describe ".secret_for" do
    context "with environment variables set" do
      before do
        # Reset all environment variables to nil first to avoid interference
        allow(ENV).to receive(:[]).and_return(nil)

        # Then mock specific ones we want to test
        allow(ENV).to receive(:[]).with("GITHUB_WEBHOOK_SECRET").and_return("env_github_secret")
        allow(ENV).to receive(:[]).with("JIRA_WEBHOOK_SECRET").and_return("env_jira_secret")
      end

      it "returns the correct secret for GitHub" do
        result = WebhookAuthenticator.secret_for("github")
        expect(result).to eq("env_github_secret")
      end

      it "returns the correct secret for Jira" do
        result = WebhookAuthenticator.secret_for("jira")
        expect(result).to eq("env_jira_secret")
      end
    end

    context "with Rails credentials set" do
      before do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:github,
                                                                   :webhook_secret).and_return("cred_github_secret")
        allow(Rails.application.credentials).to receive(:dig).with(:jira,
                                                                   :webhook_secret).and_return("cred_jira_secret")
      end

      it "returns the correct secret for GitHub from credentials" do
        expect(WebhookAuthenticator.secret_for("github")).to eq("cred_github_secret")
      end

      it "returns the correct secret for Jira from credentials" do
        expect(WebhookAuthenticator.secret_for("jira")).to eq("cred_jira_secret")
      end
    end

    context "with no specific configuration" do
      before do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      end

      it "returns the demo token as fallback" do
        expect(WebhookAuthenticator.secret_for("github")).to eq("demo_secret_token")
      end
    end
  end
end
