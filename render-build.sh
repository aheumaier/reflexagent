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

# Run migrations if database connection is available
if bin/rails db:version >/dev/null 2>&1; then
  echo "Database exists, running migrations..."
  bin/rails db:migrate
else
  echo "Database doesn't exist or can't connect, creating and migrating..."
  bin/rails db:create db:migrate db:seed
fi