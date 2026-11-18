# frozen_string_literal: true

if Rails.env.local?
  require 'rbs_rails/rake_task'
  RbsRails::RakeTask.new
end
