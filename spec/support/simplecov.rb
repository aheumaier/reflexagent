# spec/support/simplecov.rb
require 'simplecov'

SimpleCov.start 'rails' do
  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/lib/tasks/'

  add_group 'Core', 'app/core'
  add_group 'Ports', 'app/ports'
  add_group 'Adapters', 'app/adapters'
  add_group 'Controllers', 'app/controllers'
  add_group 'Models', 'app/models'
end
