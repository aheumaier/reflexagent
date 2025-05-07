#!/usr/bin/env ruby
# frozen_string_literal: true

# This script fixes controller specs to use request specs instead
require 'fileutils'

def process_file(file_path)
  puts "Processing: #{file_path}"
  content = File.read(file_path)
  original = content.dup

  # Fix controller and request specs
  if file_path.match?(/spec\/(integration|e2e).*_spec\.rb/)
    # Change controller specs to request specs
    content = content.gsub(/RSpec\.describe\s+(\w+::\w+::\w+Controller),\s+type:\s+:controller/, 'RSpec.describe "\1", type: :request')
    content = content.gsub(/RSpec\.describe\s+(\w+::\w+Controller),\s+type:\s+:controller/, 'RSpec.describe "\1", type: :request')

    # Convert controller spec to request spec syntax
    content = content.gsub(/get\s+:(\w+),\s+params:\s+\{\s*([^}]+)\s*\}/, 'get "\1?\2"')
    content = content.gsub(/post\s+:(\w+),\s+params:\s+\{\s*([^}]+)\s*\}/, 'post "\1?\2"')
    content = content.gsub(/put\s+:(\w+),\s+params:\s+\{\s*([^}]+)\s*\}/, 'put "\1?\2"')
    content = content.gsub(/delete\s+:(\w+),\s+params:\s+\{\s*([^}]+)\s*\}/, 'delete "\1?\2"')

    # Add request helpers inclusion
    unless content.include?('include Rails.application.routes.url_helpers')
      content = content.gsub(/(RSpec\.describe.*do)/, "\\1\n  include Rails.application.routes.url_helpers\n")
    end
  end

  # Only write back if changes were made
  if content != original
    File.write(file_path, content)
    puts "  Updated file: #{file_path}"
  else
    puts "  No changes needed for #{file_path}"
  end
end

# Process all controller and request specs
Dir.glob("spec/{integration,e2e}/**/*_controller_spec.rb").each do |file_path|
  process_file(file_path)
end

puts "Done! Fixed controller specs to use request specs instead."
