#!/usr/bin/env ruby
# frozen_string_literal: true

# This script fixes require_relative paths in test files after reorganizing the test structure
require 'fileutils'

def process_file(file_path)
  puts "Processing: #{file_path}"
  content = File.read(file_path)
  original = content.dup

  # Fix the specific pattern we're seeing in the files
  if file_path.match?(/spec\/(unit|integration|e2e)/)
    # First add a require for rails_helper if it's not already present
    unless content.include?('require "rails_helper"') || content.include?("require 'rails_helper'")
      content = "require 'rails_helper'\n\n" + content
    end

    # Remove problematic require_relative statements for app code
    content = content.gsub(/require_relative\s+["']\.\.\/\.\.\/\.\.\/adapters\/.*?["']/, '')
    content = content.gsub(/require_relative\s+["']\.\.\/\.\.\/\.\.\/core\/.*?["']/, '')
    content = content.gsub(/require_relative\s+["']\.\.\/\.\.\/\.\.\/ports\/.*?["']/, '')
    content = content.gsub(/require_relative\s+["']\.\.\/\.\.\/\.\.\/.*?["']/, '')
    content = content.gsub(/require_relative\s+["']\.\.\/\.\.\/.*?["']/, '')

    # Remove extra blank lines that might be created
    content = content.gsub(/\n\n+/, "\n\n")
  end

  # Only write back if changes were made
  if content != original
    File.write(file_path, content)
    puts "  Updated require paths in #{file_path}"
  else
    puts "  No changes needed in #{file_path}"
  end
end

# Process all test files in the problematic folders
Dir.glob("spec/{unit,integration,e2e}/**/*_spec.rb").each do |file_path|
  process_file(file_path)
end

puts "Done! Fixed require_relative paths in test files."
