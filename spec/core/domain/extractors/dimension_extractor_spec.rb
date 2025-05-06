# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::Extractors::DimensionExtractor do
  let(:extractor) { described_class.new }

  describe "#extract_dimensions" do
    context "with a GitHub event" do
      let(:github_event) { FactoryBot.build(:event, name: "github.push", source: "github") }

      it "delegates to extract_github_dimensions" do
        allow(extractor).to receive(:extract_github_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(github_event)

        expect(extractor).to have_received(:extract_github_dimensions).with(github_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Jira event" do
      let(:jira_event) { FactoryBot.build(:event, name: "jira.issue.created", source: "jira") }

      it "delegates to extract_jira_dimensions" do
        allow(extractor).to receive(:extract_jira_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(jira_event)

        expect(extractor).to have_received(:extract_jira_dimensions).with(jira_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a GitLab event" do
      let(:gitlab_event) { FactoryBot.build(:event, name: "gitlab.push", source: "gitlab") }

      it "delegates to extract_gitlab_dimensions" do
        allow(extractor).to receive(:extract_gitlab_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(gitlab_event)

        expect(extractor).to have_received(:extract_gitlab_dimensions).with(gitlab_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Bitbucket event" do
      let(:bitbucket_event) { FactoryBot.build(:event, name: "bitbucket.push", source: "bitbucket") }

      it "delegates to extract_bitbucket_dimensions" do
        allow(extractor).to receive(:extract_bitbucket_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(bitbucket_event)

        expect(extractor).to have_received(:extract_bitbucket_dimensions).with(bitbucket_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a CI event" do
      let(:ci_event) { FactoryBot.build(:event, name: "ci.build.completed", source: "jenkins") }

      it "delegates to extract_ci_dimensions" do
        allow(extractor).to receive(:extract_ci_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(ci_event)

        expect(extractor).to have_received(:extract_ci_dimensions).with(ci_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with a Task event" do
      let(:task_event) { FactoryBot.build(:event, name: "task.created", source: "asana") }

      it "delegates to extract_task_dimensions" do
        allow(extractor).to receive(:extract_task_dimensions).and_return({ test: "value" })

        result = extractor.extract_dimensions(task_event)

        expect(extractor).to have_received(:extract_task_dimensions).with(task_event)
        expect(result).to eq({ test: "value" })
      end
    end

    context "with an unknown event source" do
      let(:unknown_event) { FactoryBot.build(:event, name: "unknown.event", source: "custom") }

      it "returns a basic dimension hash with source" do
        result = extractor.extract_dimensions(unknown_event)

        expect(result).to eq({ source: "custom" })
      end
    end
  end

  describe "#extract_github_dimensions" do
    let(:github_event) do
      FactoryBot.build(:event,
                       name: "github.push",
                       source: "github",
                       data: { repository: { full_name: "octocat/hello-world" } })
    end

    it "extracts repository name and organization" do
      dimensions = extractor.extract_github_dimensions(github_event)

      expect(dimensions[:repository]).to eq("octocat/hello-world")
      expect(dimensions[:organization]).to eq("octocat")
      expect(dimensions[:source]).to eq("github")
    end

    context "when repository info is missing" do
      let(:github_event_no_repo) { FactoryBot.build(:event, name: "github.push", source: "github", data: {}) }

      it "uses 'unknown' as fallback" do
        dimensions = extractor.extract_github_dimensions(github_event_no_repo)

        expect(dimensions[:repository]).to eq("unknown")
        expect(dimensions[:organization]).to eq("unknown")
        expect(dimensions[:source]).to eq("github")
      end
    end
  end

  describe "#extract_org_from_repo" do
    it "returns the organization part from a repo name" do
      org = extractor.extract_org_from_repo("octocat/hello-world")
      expect(org).to eq("octocat")
    end

    it "returns 'unknown' for nil repo name" do
      org = extractor.extract_org_from_repo(nil)
      expect(org).to eq("unknown")
    end
  end

  describe "#extract_commit_count" do
    let(:push_event) do
      FactoryBot.build(:event, data: { commits: [1, 2, 3] })
    end

    let(:event_no_commits) do
      FactoryBot.build(:event, data: {})
    end

    it "returns the count of commits" do
      count = extractor.extract_commit_count(push_event)
      expect(count).to eq(3)
    end

    it "returns 1 when no commits are present" do
      count = extractor.extract_commit_count(event_no_commits)
      expect(count).to eq(1)
    end
  end

  describe "#extract_author" do
    let(:event_with_sender) do
      FactoryBot.build(:event, data: { sender: { login: "octocat" } })
    end

    let(:event_with_pusher) do
      FactoryBot.build(:event, data: { pusher: { name: "octopus" } })
    end

    let(:event_no_author) do
      FactoryBot.build(:event, data: {})
    end

    it "extracts author from sender.login" do
      author = extractor.extract_author(event_with_sender)
      expect(author).to eq("octocat")
    end

    it "falls back to pusher.name if sender is missing" do
      author = extractor.extract_author(event_with_pusher)
      expect(author).to eq("octopus")
    end

    it "returns 'unknown' if no author info is available" do
      author = extractor.extract_author(event_no_author)
      expect(author).to eq("unknown")
    end
  end

  describe "#extract_branch" do
    let(:event_with_branch) do
      FactoryBot.build(:event, data: { ref: "refs/heads/main" })
    end

    let(:event_with_tag) do
      FactoryBot.build(:event, data: { ref: "refs/tags/v1.0.0" })
    end

    let(:event_no_ref) do
      FactoryBot.build(:event, data: {})
    end

    it "extracts branch name from refs/heads/" do
      branch = extractor.extract_branch(event_with_branch)
      expect(branch).to eq("main")
    end

    it "extracts tag name from refs/tags/" do
      branch = extractor.extract_branch(event_with_tag)
      expect(branch).to eq("v1.0.0")
    end

    it "returns 'unknown' if ref is missing" do
      branch = extractor.extract_branch(event_no_ref)
      expect(branch).to eq("unknown")
    end
  end

  describe "#extract_conventional_commit_parts" do
    it "correctly parses a feature commit" do
      commit = { message: "feat(users): add login functionality" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("feat")
      expect(result[:commit_scope]).to eq("users")
      expect(result[:commit_description]).to eq("add login functionality")
      expect(result[:commit_breaking]).to be(false)
      expect(result[:commit_conventional]).to be(true)
    end

    it "correctly parses a fix commit" do
      commit = { message: "fix: correct calculation error" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("fix")
      expect(result[:commit_scope]).to be_nil
      expect(result[:commit_description]).to eq("correct calculation error")
      expect(result[:commit_breaking]).to be(false)
      expect(result[:commit_conventional]).to be(true)
    end

    it "identifies breaking changes with exclamation mark" do
      commit = { message: "feat(api)!: change return format" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("feat")
      expect(result[:commit_scope]).to eq("api")
      expect(result[:commit_description]).to eq("change return format")
      expect(result[:commit_breaking]).to be(true)
      expect(result[:commit_conventional]).to be(true)
    end

    it "handles complex scopes with paths" do
      commit = { message: "refactor(core/api/users): simplify authentication flow" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("refactor")
      expect(result[:commit_scope]).to eq("core/api/users")
      expect(result[:commit_description]).to eq("simplify authentication flow")
      expect(result[:commit_conventional]).to be(true)
    end

    it "handles scopes with hyphens and underscores" do
      commit = { message: "chore(github-auth_flow): update dependencies" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("chore")
      expect(result[:commit_scope]).to eq("github-auth_flow")
      expect(result[:commit_description]).to eq("update dependencies")
      expect(result[:commit_conventional]).to be(true)
    end

    it "handles breaking changes with detailed description" do
      commit = { message: "feat(db)!: migrate to PostgreSQL 14\n\nBREAKING CHANGE: requires updated client libraries" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_type]).to eq("feat")
      expect(result[:commit_scope]).to eq("db")
      expect(result[:commit_breaking]).to be(true)
      expect(result[:commit_description]).to include("migrate to PostgreSQL 14")
      expect(result[:commit_conventional]).to be(true)
    end

    it "supports all common conventional commit types" do
      types = ["feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert"]

      types.each do |type|
        commit = { message: "#{type}: do something" }
        result = extractor.extract_conventional_commit_parts(commit)

        expect(result[:commit_type]).to eq(type)
        expect(result[:commit_conventional]).to be(true)
      end
    end

    it "handles non-conventional commit messages with type inference" do
      commit = { message: "Fixed the login bug" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_conventional]).to be(false)
      expect(result[:commit_description]).to eq("Fixed the login bug")
      expect(result[:commit_type]).to eq("fix")
      expect(result[:commit_type_inferred]).to be(true)
    end

    it "infers type from non-conventional commit with feature-like message" do
      commit = { message: "Add new user registration form" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_conventional]).to be(false)
      expect(result[:commit_type]).to eq("feat")
      expect(result[:commit_type_inferred]).to be(true)
    end

    it "infers type from non-conventional commit with refactor-like message" do
      commit = { message: "Refactored the authentication flow" }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_conventional]).to be(false)
      expect(result[:commit_type]).to eq("refactor")
      expect(result[:commit_type_inferred]).to be(true)
    end

    it "handles empty or nil messages" do
      commit = { message: nil }
      result = extractor.extract_conventional_commit_parts(commit)

      expect(result[:commit_conventional]).to be(false)
      expect(result[:commit_description]).to eq("")
      # Should default to chore for empty messages
      expect(result[:commit_type]).to eq("chore")
    end
  end

  describe "#infer_commit_type" do
    it "infers 'fix' from bug-related messages" do
      expect(extractor.infer_commit_type("Fixed a bug in login")).to eq("fix")
      expect(extractor.infer_commit_type("Bug fix for payment processing")).to eq("fix")
      expect(extractor.infer_commit_type("Resolve issue with signup form")).to eq("fix")
      expect(extractor.infer_commit_type("Patch security vulnerability")).to eq("fix")
    end

    it "infers 'feat' from feature-related messages" do
      expect(extractor.infer_commit_type("Added new dashboard")).to eq("feat")
      expect(extractor.infer_commit_type("Implement user preferences")).to eq("feat")
      expect(extractor.infer_commit_type("New export functionality")).to eq("feat")
      expect(extractor.infer_commit_type("Introducing dark mode")).to eq("feat")
    end

    it "infers 'docs' from documentation-related messages" do
      expect(extractor.infer_commit_type("Update README with installation steps")).to eq("docs")
      expect(extractor.infer_commit_type("Documentation for API endpoints")).to eq("docs")
      expect(extractor.infer_commit_type("Add comments to complex functions")).to eq("docs")
    end

    it "infers 'style' from style-related messages" do
      expect(extractor.infer_commit_type("Format code according to style guide")).to eq("style")
      expect(extractor.infer_commit_type("Fix indentation in module")).to eq("style")
      expect(extractor.infer_commit_type("CSS styling for buttons")).to eq("style")
    end

    it "infers 'refactor' from refactoring-related messages" do
      expect(extractor.infer_commit_type("Refactor user service")).to eq("refactor")
      expect(extractor.infer_commit_type("Simplify authentication logic")).to eq("refactor")
      expect(extractor.infer_commit_type("Clean up redundant code")).to eq("refactor")
    end

    it "infers 'test' from testing-related messages" do
      expect(extractor.infer_commit_type("Add unit tests for auth service")).to eq("test")
      expect(extractor.infer_commit_type("Testing payment workflow")).to eq("test")
      expect(extractor.infer_commit_type("Improve test coverage")).to eq("test")
    end

    it "infers 'chore' from maintenance-related messages" do
      expect(extractor.infer_commit_type("Update dependencies")).to eq("chore")
      expect(extractor.infer_commit_type("Version bump to 2.1.0")).to eq("chore")
      expect(extractor.infer_commit_type("Maintenance for CI pipeline")).to eq("chore")
    end

    it "infers 'perf' from performance-related messages" do
      expect(extractor.infer_commit_type("Optimize database queries")).to eq("perf")
      expect(extractor.infer_commit_type("Performance improvements for search")).to eq("perf")
      expect(extractor.infer_commit_type("Speed up page load times")).to eq("perf")
    end

    it "uses file context to determine commit type" do
      # Test files
      expect(extractor.infer_commit_type("Updated test case", modified: ["spec/models/user_spec.rb"])).to eq("test")

      # Documentation files
      expect(extractor.infer_commit_type("Updated installation steps", added: ["README.md"])).to eq("docs")

      # Style files
      expect(extractor.infer_commit_type("Adjust button colors",
                                         modified: ["app/assets/stylesheets/buttons.scss"])).to eq("style")
    end

    it "handles special cases for WIP and Merge commits" do
      expect(extractor.infer_commit_type("WIP")).to eq("chore")
      expect(extractor.infer_commit_type("Merge pull request #123")).to eq("chore")
      expect(extractor.infer_commit_type("Merge branch 'feature/xyz' into main")).to eq("chore")
    end

    it "uses fallback patterns for ambiguous messages" do
      expect(extractor.infer_commit_type("Remove obsolete code")).to eq("refactor")
      expect(extractor.infer_commit_type("Update translations")).to eq("chore")
      expect(extractor.infer_commit_type("Something completely unrelated")).to eq("chore")
    end
  end

  describe "#extract_file_changes" do
    let(:push_event) do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        {
          added: ["src/users/login.rb", "src/users/logout.rb"],
          modified: ["src/app.rb", "config/routes.rb"],
          removed: ["old_file.rb"]
        },
        {
          added: ["src/users/signup.rb"],
          modified: ["src/users/model.rb"],
          removed: []
        }
      ]
      event
    end

    let(:event_without_commits) do
      FactoryBot.build(:event, name: "github.issues.opened", source: "github")
    end

    it "counts files correctly" do
      result = extractor.extract_file_changes(push_event)

      expect(result[:files_added]).to eq(3)
      expect(result[:files_modified]).to eq(3)
      expect(result[:files_removed]).to eq(1)
    end

    it "returns full file paths" do
      result = extractor.extract_file_changes(push_event)

      expect(result[:file_paths_added]).to include(
        "src/users/login.rb", "src/users/logout.rb", "src/users/signup.rb"
      )
      expect(result[:file_paths_modified]).to include(
        "src/app.rb", "config/routes.rb", "src/users/model.rb"
      )
      expect(result[:file_paths_removed]).to include("old_file.rb")
    end

    it "handles events without commits" do
      result = extractor.extract_file_changes(event_without_commits)

      expect(result[:files_added]).to eq(0)
      expect(result[:files_modified]).to eq(0)
      expect(result[:files_removed]).to eq(0)
    end
  end

  describe "#analyze_directories" do
    let(:files) do
      [
        "src/users/login.rb",
        "src/users/logout.rb",
        "src/users/signup.rb",
        "src/app.rb",
        "config/routes.rb",
        "config/database.yml"
      ]
    end

    it "identifies directory hotspots" do
      result = extractor.analyze_directories(files)

      expect(result[:directory_hotspots]).to include("src/users" => 3, "src" => 4, "config" => 2)
      expect(result[:top_directory]).to eq("src")
      expect(result[:top_directory_count]).to eq(4)
    end

    it "handles empty file list" do
      result = extractor.analyze_directories([])

      expect(result).to eq({})
    end

    it "correctly analyzes nested paths" do
      result = extractor.analyze_directories(["a/b/c/d.rb", "a/b/e.rb", "a/f.rb"])

      expect(result[:directory_hotspots]).to include(
        "a" => 3,
        "a/b" => 2,
        "a/b/c" => 1
      )
    end

    it "correctly analyzes deeply nested paths" do
      deeply_nested_files = [
        "app/models/concerns/searchable.rb",
        "app/models/concerns/taggable.rb",
        "app/models/user.rb",
        "app/controllers/api/v1/users_controller.rb",
        "app/controllers/api/v1/posts_controller.rb",
        "app/controllers/api/v2/users_controller.rb",
        "lib/tasks/data_migration.rb",
        "lib/tasks/cleanup.rb"
      ]

      result = extractor.analyze_directories(deeply_nested_files)

      expect(result[:directory_hotspots]).to include(
        "app" => 6,
        "app/models" => 3,
        "app/models/concerns" => 2,
        "app/controllers" => 3,
        "app/controllers/api" => 3,
        "app/controllers/api/v1" => 2,
        "app/controllers/api/v2" => 1,
        "lib" => 2,
        "lib/tasks" => 2
      )

      expect(result[:top_directory]).to eq("app")
      expect(result[:top_directory_count]).to eq(6)
    end

    it "correctly prioritizes hotspots across similar structures" do
      similar_structured_files = [
        "frontend/components/users/profile.js",
        "frontend/components/users/settings.js",
        "frontend/components/users/avatar.js",
        "frontend/components/posts/list.js",
        "frontend/components/posts/detail.js",
        "backend/controllers/users_controller.rb",
        "backend/controllers/posts_controller.rb"
      ]

      result = extractor.analyze_directories(similar_structured_files)

      # Verify the order of hotspots is correct
      ordered_hotspots = result[:directory_hotspots].to_a

      expect(ordered_hotspots[0][0]).to eq("frontend")
      expect(ordered_hotspots[0][1]).to eq(5)

      expect(ordered_hotspots[1][0]).to eq("frontend/components")
      expect(ordered_hotspots[1][1]).to eq(5)

      expect(result[:directory_hotspots]["frontend/components/users"]).to eq(3)
      expect(result[:directory_hotspots]["frontend/components/posts"]).to eq(2)
    end

    it "handles files in the root directory" do
      root_files = [
        "README.md",
        "Gemfile",
        "Rakefile",
        "config/routes.rb"
      ]

      result = extractor.analyze_directories(root_files)

      # Root files don't count as directories
      expect(result[:directory_hotspots]).to have_key("config")
      expect(result[:directory_hotspots].keys).not_to include("")
      expect(result[:directory_hotspots]["config"]).to eq(1)
    end
  end

  describe "#analyze_extensions" do
    let(:files) do
      [
        "src/users/login.rb",
        "src/users/logout.rb",
        "src/app.rb",
        "config/routes.rb",
        "config/database.yml",
        "README.md",
        "Dockerfile"
      ]
    end

    it "counts file extensions correctly" do
      result = extractor.analyze_extensions(files)

      expect(result[:extension_hotspots]).to include("rb" => 4, "yml" => 1, "md" => 1)
      expect(result[:top_extension]).to eq("rb")
      expect(result[:top_extension_count]).to eq(4)
    end

    it "handles files without extensions" do
      result = extractor.analyze_extensions(["Dockerfile", "LICENSE", ".gitignore"])

      expect(result[:extension_hotspots]).to include("no_extension" => 3)
    end

    it "handles empty file list" do
      result = extractor.analyze_extensions([])

      expect(result).to eq({})
    end

    it "normalizes extensions to lowercase" do
      mixed_case_files = [
        "component.JSX",
        "module.Ts",
        "styles.CSS",
        "config.JSON"
      ]

      result = extractor.analyze_extensions(mixed_case_files)

      expect(result[:extension_hotspots]).to include(
        "jsx" => 1,
        "ts" => 1,
        "css" => 1,
        "json" => 1
      )

      # Should not have any uppercase extensions
      expect(result[:extension_hotspots].keys.any? { |ext| ext =~ /[A-Z]/ }).to be(false)
    end

    it "handles complex web application file types" do
      web_app_files = [
        "components/Button.tsx",
        "components/Form.tsx",
        "styles/main.scss",
        "styles/variables.scss",
        "public/logo.svg",
        "public/background.jpg",
        "public/fonts/roboto.woff2",
        "webpack.config.js",
        "package.json",
        "tsconfig.json",
        ".babelrc",
        ".eslintrc.js"
      ]

      result = extractor.analyze_extensions(web_app_files)

      expect(result[:extension_hotspots]).to include(
        "tsx" => 2,
        "scss" => 2,
        "json" => 2,
        "js" => 2
      )

      # Images and fonts should also be counted
      expect(result[:extension_hotspots]["svg"]).to eq(1)
      expect(result[:extension_hotspots]["jpg"]).to eq(1)
      expect(result[:extension_hotspots]["woff2"]).to eq(1)
    end

    it "handles files with multiple dots" do
      multi_dot_files = [
        "archive.tar.gz",
        "config.dev.json",
        "index.test.js",
        "component.stories.tsx",
        "README.zh-CN.md"
      ]

      result = extractor.analyze_extensions(multi_dot_files)

      # Should use only the last extension
      expect(result[:extension_hotspots]).to include(
        "gz" => 1,
        "json" => 1,
        "js" => 1,
        "tsx" => 1,
        "md" => 1
      )

      # Should not include compound extensions
      expect(result[:extension_hotspots].keys).not_to include("tar.gz")
      expect(result[:extension_hotspots].keys).not_to include("dev.json")
      expect(result[:extension_hotspots].keys).not_to include("test.js")
    end

    it "handles dotfiles correctly" do
      dotfiles = [
        ".gitignore",
        ".env",
        ".env.local",
        ".ruby-version",
        ".dockerignore"
      ]

      result = extractor.analyze_extensions(dotfiles)

      expect(result[:extension_hotspots]).to include(
        "no_extension" => 4,
        "local" => 1
      )
    end
  end

  describe "#extract_code_volume" do
    let(:push_event_with_stats) do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: 10, deletions: 5 } },
        { stats: { additions: 20, deletions: 8 } }
      ]
      event
    end

    let(:push_event_without_stats) do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { message: "Add new feature" },
        { message: "Fix bug" }
      ]
      event
    end

    let(:event_without_commits) do
      FactoryBot.build(:event, name: "github.issues.opened", source: "github")
    end

    it "sums up code additions and deletions" do
      result = extractor.extract_code_volume(push_event_with_stats)

      expect(result[:code_additions]).to eq(30)
      expect(result[:code_deletions]).to eq(13)
      expect(result[:code_churn]).to eq(43)
    end

    it "handles commits without stats" do
      result = extractor.extract_code_volume(push_event_without_stats)

      expect(result[:code_additions]).to eq(0)
      expect(result[:code_deletions]).to eq(0)
      expect(result[:code_churn]).to eq(0)
    end

    it "handles events without commits" do
      result = extractor.extract_code_volume(event_without_commits)

      expect(result[:code_additions]).to eq(0)
      expect(result[:code_deletions]).to eq(0)
      expect(result[:code_churn]).to eq(0)
    end

    it "handles large code changes" do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: 5000, deletions: 3000 } },
        { stats: { additions: 2500, deletions: 1800 } }
      ]

      result = extractor.extract_code_volume(event)

      expect(result[:code_additions]).to eq(7500)
      expect(result[:code_deletions]).to eq(4800)
      expect(result[:code_churn]).to eq(12_300)
    end

    it "handles zero code changes" do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: 0, deletions: 0 } }
      ]

      result = extractor.extract_code_volume(event)

      expect(result[:code_additions]).to eq(0)
      expect(result[:code_deletions]).to eq(0)
      expect(result[:code_churn]).to eq(0)
    end

    it "handles string values for additions and deletions" do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: "15", deletions: "7" } }
      ]

      result = extractor.extract_code_volume(event)

      expect(result[:code_additions]).to eq(15)
      expect(result[:code_deletions]).to eq(7)
      expect(result[:code_churn]).to eq(22)
    end

    it "handles many commits with varying code changes" do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: { additions: 5, deletions: 2 } },
        { stats: { additions: 0, deletions: 10 } },
        { stats: { additions: 15, deletions: 0 } },
        { stats: { additions: 8, deletions: 8 } },
        { stats: { additions: 3, deletions: 1 } }
      ]

      result = extractor.extract_code_volume(event)

      expect(result[:code_additions]).to eq(31)
      expect(result[:code_deletions]).to eq(21)
      expect(result[:code_churn]).to eq(52)
    end

    it "handles missing stats fields gracefully" do
      event = FactoryBot.build(:event, name: "github.push", source: "github")
      event.data[:commits] = [
        { stats: {} }, # Empty stats
        { stats: { additions: 10 } }, # Missing deletions
        { stats: { deletions: 5 } }, # Missing additions
        { stats: nil } # Nil stats
      ]

      result = extractor.extract_code_volume(event)

      expect(result[:code_additions]).to eq(10)
      expect(result[:code_deletions]).to eq(5)
      expect(result[:code_churn]).to eq(15)
    end
  end
end
