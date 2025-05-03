# frozen_string_literal: true

module Domain
  # The MetricClassifier is responsible for analyzing events and determining
  # which metrics should be created from them.
  #
  # It maps different event types to appropriate metrics with their dimensions,
  # creating a configurable way to generate metrics from incoming events.
  class MetricClassifier
    # Analyzes an event and returns a classification of metrics to be created
    #
    # @param event [Domain::Event] The event to classify
    # @return [Hash] A hash with a :metrics key containing an array of metric definitions
    def classify_event(event)
      event_type = event.name

      # Dispatch to the appropriate handler based on the event type pattern
      case event_type
      when /^github\./
        classify_github_event(event)
      when /^jira\./
        classify_jira_event(event)
      when /^gitlab\./
        classify_gitlab_event(event)
      when /^bitbucket\./
        classify_bitbucket_event(event)
      when /^ci\./
        classify_ci_event(event)
      when /^task\./
        classify_task_event(event)
      else
        classify_generic_event(event)
      end
    end

    private

    # Classification handlers for different event source types

    def classify_github_event(event)
      # Extract the main event type and action from the event name
      # Format should be: github.[event_name].[action]
      _, event_name, action = event.name.split(".")

      # Handle GitHub events based on standardized event names from GitHub Webhook API
      case event_name
      when "push"
        classify_github_push_event(event)
      when "pull_request"
        classify_github_pull_request_event(event, action)
      when "issues"
        classify_github_issues_event(event, action)
      when "check_run"
        classify_github_check_run_event(event, action)
      when "check_suite"
        classify_github_check_suite_event(event, action)
      when "create"
        classify_github_create_event(event)
      when "delete"
        classify_github_delete_event(event)
      when "deployment"
        classify_github_deployment_event(event)
      when "deployment_status"
        classify_github_deployment_status_event(event, action)
      when "workflow_run"
        classify_github_workflow_run_event(event, action)
      when "workflow_job"
        classify_github_workflow_job_event(event, action)
      when "workflow_dispatch"
        classify_github_workflow_dispatch_event(event)
      else
        # Generic GitHub event
        {
          metrics: [
            {
              name: "github.#{event_name}.#{action || 'total'}",
              value: 1,
              dimensions: extract_repo_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_github_push_event(event)
      {
        metrics: [
          # Count of push events
          {
            name: "github.push.total",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          # Count of commits in this push
          {
            name: "github.push.commits",
            value: extract_commit_count(event),
            dimensions: extract_repo_dimensions(event)
          },
          # Track unique authors
          {
            name: "github.push.unique_authors",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(
              author: extract_author(event)
            )
          },
          # Track commits by branch
          {
            name: "github.push.branch_activity",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(
              branch: extract_branch(event)
            )
          }
        ]
      }
    end

    # Renamed from classify_github_pr_event to match GitHub's API naming
    def classify_github_pull_request_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"

      {
        metrics: [
          # Total PRs
          {
            name: "github.pull_request.total",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(action: action)
          },
          # PR action count (opened, closed, merged, etc.)
          {
            name: "github.pull_request.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          # Track PR by author
          {
            name: "github.pull_request.by_author",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(
              author: extract_author(event),
              action: action
            )
          }
        ]
      }
    end

    # Renamed from classify_github_issue_event to match GitHub's API naming
    def classify_github_issues_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"

      {
        metrics: [
          # Total issues
          {
            name: "github.issues.total",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(action: action)
          },
          # Issue action count
          {
            name: "github.issues.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          # Issues by author
          {
            name: "github.issues.by_author",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(
              author: extract_author(event),
              action: action
            )
          }
        ]
      }
    end

    # New method for check_run events
    def classify_github_check_run_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"

      {
        metrics: [
          {
            name: "github.check_run.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for check_suite events
    def classify_github_check_suite_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"

      {
        metrics: [
          {
            name: "github.check_suite.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for create events (branch/tag creation)
    def classify_github_create_event(event)
      ref_type = event.data[:ref_type] || "unknown"

      {
        metrics: [
          {
            name: "github.create.total",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          {
            name: "github.create.#{ref_type}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for delete events (branch/tag deletion)
    def classify_github_delete_event(event)
      ref_type = event.data[:ref_type] || "unknown"

      {
        metrics: [
          {
            name: "github.delete.total",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          {
            name: "github.delete.#{ref_type}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for deployment events
    def classify_github_deployment_event(event)
      environment = event.data.dig(:deployment, :environment) || "unknown"

      {
        metrics: [
          {
            name: "github.deployment.total",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          {
            name: "github.deployment.environment",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(environment: environment)
          }
        ]
      }
    end

    # New method for deployment_status events
    def classify_github_deployment_status_event(event, action)
      environment = event.data.dig(:deployment, :environment) || "unknown"
      state = event.data.dig(:deployment_status, :state) || "unknown"

      {
        metrics: [
          {
            name: "github.deployment_status.total",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(
              environment: environment,
              state: state
            )
          },
          {
            name: "github.deployment_status.#{state}",
            value: 1,
            dimensions: extract_repo_dimensions(event).merge(environment: environment)
          }
        ]
      }
    end

    # New method for workflow_run events
    def classify_github_workflow_run_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"
      conclusion = event.data.dig(:workflow_run, :conclusion) || "unknown"

      {
        metrics: [
          {
            name: "github.workflow_run.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          {
            name: "github.workflow_run.conclusion.#{conclusion}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for workflow_job events
    def classify_github_workflow_job_event(event, action)
      # Default to 'total' if action is nil
      action ||= "total"
      conclusion = event.data.dig(:workflow_job, :conclusion) || "unknown"

      {
        metrics: [
          {
            name: "github.workflow_job.#{action}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          },
          {
            name: "github.workflow_job.conclusion.#{conclusion}",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    # New method for workflow_dispatch events
    def classify_github_workflow_dispatch_event(event)
      {
        metrics: [
          {
            name: "github.workflow_dispatch.total",
            value: 1,
            dimensions: extract_repo_dimensions(event)
          }
        ]
      }
    end

    def classify_jira_event(event)
      event_subtype = event.name.sub("jira.", "")

      case event_subtype
      when /^issue_(created|updated|resolved|deleted)$/
        action = ::Regexp.last_match(1)
        {
          metrics: [
            # Total issues
            {
              name: "jira.issue.total",
              value: 1,
              dimensions: extract_jira_dimensions(event).merge(action: action)
            },
            # Issues by action type
            {
              name: "jira.issue.#{action}",
              value: 1,
              dimensions: extract_jira_dimensions(event)
            },
            # Issues by type
            {
              name: "jira.issue.by_type",
              value: 1,
              dimensions: extract_jira_dimensions(event).merge(
                issue_type: extract_jira_issue_type(event),
                action: action
              )
            }
          ]
        }
      when /^sprint_(started|closed)$/
        action = ::Regexp.last_match(1)
        {
          metrics: [
            {
              name: "jira.sprint.#{action}",
              value: 1,
              dimensions: extract_jira_dimensions(event)
            }
          ]
        }
      else
        # Generic Jira event
        {
          metrics: [
            {
              name: "jira.#{event_subtype}.total",
              value: 1,
              dimensions: extract_jira_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_gitlab_event(event)
      event_subtype = event.name.sub("gitlab.", "")

      case event_subtype
      when "push"
        {
          metrics: [
            {
              name: "gitlab.push.total",
              value: 1,
              dimensions: extract_gitlab_dimensions(event)
            },
            {
              name: "gitlab.push.commits",
              value: extract_gitlab_commit_count(event),
              dimensions: extract_gitlab_dimensions(event)
            }
          ]
        }
      when /^merge_request\.(opened|closed|merged)$/
        action = ::Regexp.last_match(1)
        {
          metrics: [
            {
              name: "gitlab.merge_request.total",
              value: 1,
              dimensions: extract_gitlab_dimensions(event).merge(action: action)
            },
            {
              name: "gitlab.merge_request.#{action}",
              value: 1,
              dimensions: extract_gitlab_dimensions(event)
            }
          ]
        }
      else
        # Generic GitLab event
        {
          metrics: [
            {
              name: "gitlab.#{event_subtype}.total",
              value: 1,
              dimensions: extract_gitlab_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_bitbucket_event(event)
      event_subtype = event.name.sub("bitbucket.", "")

      case event_subtype
      when /^repo:push$/
        {
          metrics: [
            {
              name: "bitbucket.push.total",
              value: 1,
              dimensions: extract_bitbucket_dimensions(event)
            },
            {
              name: "bitbucket.push.commits",
              value: extract_bitbucket_commit_count(event),
              dimensions: extract_bitbucket_dimensions(event)
            }
          ]
        }
      when /^pullrequest:(created|approved|merged|rejected)$/
        action = ::Regexp.last_match(1)
        {
          metrics: [
            {
              name: "bitbucket.pullrequest.total",
              value: 1,
              dimensions: extract_bitbucket_dimensions(event).merge(action: action)
            },
            {
              name: "bitbucket.pullrequest.#{action}",
              value: 1,
              dimensions: extract_bitbucket_dimensions(event)
            }
          ]
        }
      else
        # Generic Bitbucket event
        {
          metrics: [
            {
              name: "bitbucket.#{event_subtype}.total",
              value: 1,
              dimensions: extract_bitbucket_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_ci_event(event)
      event_subtype = event.name.sub("ci.", "")

      # Handle special case for generic "ci.event" events that don't follow the pattern
      if event_subtype == "event"
        # Extract operation and status from payload
        operation = event.data[:operation]
        status = event.data[:status]

        if operation && status
          metrics = [
            # Total CI operations
            {
              name: "ci.#{operation}.total",
              value: 1,
              dimensions: extract_ci_dimensions(event).merge(status: status)
            },
            # CI operations by status
            {
              name: "ci.#{operation}.#{status}",
              value: 1,
              dimensions: extract_ci_dimensions(event)
            }
          ]

          # Add duration metric if operation is completed
          if status == "completed"
            metrics << {
              name: "ci.#{operation}.duration",
              value: extract_ci_duration(event),
              dimensions: extract_ci_dimensions(event)
            }

            # For deployments, add specific DORA-related metrics
            if operation == "deploy"
              # Add deploy completed metric for deployment frequency
              metrics << {
                name: "ci.deploy.completed",
                value: 1,
                dimensions: extract_ci_dimensions(event)
              }

              # Add lead time metrics if available
              if event.data[:lead_time]
                metrics << {
                  name: "ci.lead_time",
                  value: event.data[:lead_time].to_f,
                  dimensions: extract_ci_dimensions(event)
                }
              end
            end
          end

          # If it's a failed deployment, track as incident for change failure rate
          if operation == "deploy" && status == "failed"
            metrics << {
              name: "ci.deploy.incident",
              value: 1,
              dimensions: extract_ci_dimensions(event)
            }
          end

          return { metrics: metrics.compact }
        end
      end

      # Original pattern matching for structured event names
      case event_subtype
      when /^(build|deploy)\.(started|completed|failed)$/
        operation = ::Regexp.last_match(1)
        status = ::Regexp.last_match(2)
        {
          metrics: [
            # Total CI operations
            {
              name: "ci.#{operation}.total",
              value: 1,
              dimensions: extract_ci_dimensions(event).merge(status: status)
            },
            # CI operations by status
            {
              name: "ci.#{operation}.#{status}",
              value: 1,
              dimensions: extract_ci_dimensions(event)
            },
            # If completed, track duration
            if status == "completed"
              {
                name: "ci.#{operation}.duration",
                value: extract_ci_duration(event),
                dimensions: extract_ci_dimensions(event)
              }
            else
              nil
            end
          ].compact
        }
      else
        # Generic CI event
        {
          metrics: [
            {
              name: "ci.#{event_subtype}.total",
              value: 1,
              dimensions: extract_ci_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_task_event(event)
      event_subtype = event.name.sub("task.", "")

      case event_subtype
      when /^(created|completed|moved)$/
        action = ::Regexp.last_match(1)
        {
          metrics: [
            # Total tasks
            {
              name: "task.total",
              value: 1,
              dimensions: extract_task_dimensions(event).merge(action: action)
            },
            # Tasks by action
            {
              name: "task.#{action}",
              value: 1,
              dimensions: extract_task_dimensions(event)
            }
          ]
        }
      else
        # Generic task event
        {
          metrics: [
            {
              name: "task.#{event_subtype}.total",
              value: 1,
              dimensions: extract_task_dimensions(event)
            }
          ]
        }
      end
    end

    def classify_generic_event(event)
      # For events that don't match any specific pattern
      {
        metrics: [
          {
            name: "#{event.name}.total",
            value: 1,
            dimensions: { source: event.source }
          }
        ]
      }
    end

    # Dimension extraction helpers

    def extract_repo_dimensions(event)
      data = event.data
      {
        repository: data.dig(:repository, :full_name) || "unknown",
        organization: extract_org_from_repo(data.dig(:repository, :full_name)),
        source: event.source
      }
    end

    def extract_org_from_repo(repo_name)
      return "unknown" unless repo_name

      repo_name.split("/").first
    end

    def extract_commit_count(event)
      event.data[:commits]&.size || 1
    end

    def extract_author(event)
      event.data.dig(:sender, :login) ||
        event.data.dig(:pusher, :name) ||
        "unknown"
    end

    def extract_branch(event)
      ref = event.data[:ref]
      return "unknown" unless ref

      # Remove refs/heads/ or refs/tags/ prefix
      ref.gsub(%r{^refs/(heads|tags)/}, "")
    end

    def extract_jira_dimensions(event)
      data = event.data
      {
        project: data.dig(:issue, :fields, :project, :key) ||
          data.dig(:project, :key) ||
          "unknown",
        source: event.source
      }
    end

    def extract_jira_issue_type(event)
      event.data.dig(:issue, :fields, :issuetype, :name) || "unknown"
    end

    def extract_gitlab_dimensions(event)
      data = event.data
      {
        project: data.dig(:project, :path_with_namespace) || "unknown",
        source: event.source
      }
    end

    def extract_gitlab_commit_count(event)
      if event.data[:commits]
        event.data[:commits].size
      elsif event.data[:total_commits_count]
        event.data[:total_commits_count]
      else
        1
      end
    end

    def extract_bitbucket_dimensions(event)
      data = event.data
      {
        repository: data.dig(:repository, :full_name) || "unknown",
        source: event.source
      }
    end

    def extract_bitbucket_commit_count(event)
      changes = event.data.dig(:push, :changes) || []
      changes.sum { |change| change.dig(:commits)&.size || 0 }
    end

    def extract_ci_dimensions(event)
      data = event.data
      {
        project: data[:project] || "unknown",
        provider: data[:provider] || "unknown",
        source: event.source
      }
    end

    def extract_ci_duration(event)
      # Duration in seconds
      data = event.data
      start_time = data[:start_time]
      end_time = data[:end_time]

      if start_time && end_time
        begin
          Time.parse(end_time) - Time.parse(start_time)
        rescue StandardError
          0
        end
      else
        data[:duration] || 0
      end
    end

    def extract_task_dimensions(event)
      data = event.data
      {
        project: data[:project] || "unknown",
        task_type: data[:type] || "unknown",
        source: event.source
      }
    end
  end
end
