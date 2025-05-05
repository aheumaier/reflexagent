# frozen_string_literal: true

# CommitMetric provides an ActiveRecord interface to the commit_metrics view
class CommitMetric < ApplicationRecord
  # This is a read-only model as it's based on a view
  self.primary_key = "id"
  self.table_name = "commit_metrics"

  # Cannot write to a view
  def readonly?
    true
  end

  # Scopes for efficient querying
  scope :by_repository, ->(repo) { where(repository: repo) }
  scope :by_organization, ->(org) { where(organization: org) }
  scope :by_author, ->(author) { where(author: author) }
  scope :by_commit_type, ->(type) { where(commit_type: type) }
  scope :by_commit_scope, ->(scope) { where(commit_scope: scope) }
  scope :by_directory, ->(dir) { where(directory: dir) }
  scope :by_filetype, ->(type) { where(filetype: type) }
  scope :with_breaking_changes, -> { where(breaking_change: true) }
  scope :since, ->(timestamp) { where("recorded_at >= ?", timestamp) }
  scope :until, ->(timestamp) { where("recorded_at <= ?", timestamp) }
  scope :between, ->(start_time, end_time) { where(recorded_at: start_time..end_time) }

  # Analysis methods
  def self.hotspot_directories(since: 30.days.ago, limit: 10)
    select("directory, COUNT(*) AS change_count")
      .where.not(directory: nil)
      .where("recorded_at >= ?", since)
      .group(:directory)
      .order("change_count DESC")
      .limit(limit)
  end

  def self.hotspot_files_by_extension(since: 30.days.ago, limit: 10)
    select("filetype, COUNT(*) AS change_count")
      .where.not(filetype: nil)
      .where("recorded_at >= ?", since)
      .group(:filetype)
      .order("change_count DESC")
      .limit(limit)
  end

  def self.commit_type_distribution(since: 30.days.ago)
    select("commit_type, COUNT(*) AS count")
      .where.not(commit_type: nil)
      .where("recorded_at >= ?", since)
      .group(:commit_type)
      .order("count DESC")
  end

  def self.author_activity(since: 30.days.ago, limit: 10)
    select("author, COUNT(*) AS commit_count")
      .where.not(author: nil)
      .where("recorded_at >= ?", since)
      .group(:author)
      .order("commit_count DESC")
      .limit(limit)
  end

  def self.lines_changed_by_author(since: 30.days.ago)
    select("author, SUM(lines_added) AS lines_added, SUM(lines_deleted) AS lines_deleted")
      .where.not(author: nil)
      .where("recorded_at >= ?", since)
      .group(:author)
      .order("lines_added + lines_deleted DESC")
  end

  def self.breaking_changes_by_author(since: 30.days.ago)
    select("author, COUNT(*) AS breaking_count")
      .where(breaking_change: true)
      .where("recorded_at >= ?", since)
      .group(:author)
      .order("breaking_count DESC")
  end

  # Time-based analysis
  def self.commit_activity_by_day(since: 30.days.ago)
    select("DATE(recorded_at) AS day, COUNT(*) AS commit_count")
      .where("recorded_at >= ?", since)
      .group("DATE(recorded_at)")
      .order("day")
  end
end
