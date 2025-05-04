#!/usr/bin/env bash

# Exit on error
set -o errexit

# Print each command for debugging
set -x

# Install dependencies
bundle install

# For assets
yarn install
bin/rails assets:precompile
bin/rails assets:clean

# If migrating to v4 of tailwindcss-rails, configure it
bin/rails tailwindcss:build

# Run migrations if database exists
bin/rails db:migrate