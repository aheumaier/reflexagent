# spec/support/simplecov_json_formatter.rb
require "json"

module SimpleCov
  module Formatter
    class JSONFormatter
      def format(result)
        groups = {}
        result.groups.each do |name, files|
          groups[name] = {
            covered_percent: files.covered_percent.round(2),
            covered_lines: files.covered_lines.size,
            total_lines: files.lines_of_code
          }
        end

        # Safe branch coverage calculation
        branch_coverage = 0
        total_branches = 0
        covered_branches = 0

        if result.respond_to?(:branch_coverage)
          branch_coverage = result.branch_coverage&.percent&.round(2) || 0.0
          total_branches = result.branch_coverage&.total_branches || 0
          covered_branches = result.branch_coverage&.covered_branches || 0
        end

        data = {
          timestamp: Time.now.to_i,
          command_name: result.command_name,
          coverage: {
            line: result.covered_percent.round(2),
            branch: branch_coverage,
            total_branches: total_branches,
            covered_branches: covered_branches
          },
          groups: groups,
          files_count: result.files.count,
          total_lines: result.lines_of_code,
          covered_lines: result.covered_lines.size
        }

        json = JSON.pretty_generate(data)
        File.open(File.join(SimpleCov.coverage_path, "coverage.json"), "w") do |file|
          file.puts json
        end
        puts "JSON coverage report generated to coverage/coverage.json"

        json
      end
    end
  end
end
