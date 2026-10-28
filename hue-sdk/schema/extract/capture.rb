# frozen_string_literal: true

# Usage: HUE_HOST=… HUE_BRIDGE_ID=… HUE_APPLICATION_KEY=… ruby schema/extract/capture.rb CAPTURE

require 'json'
require_relative '../../lib/hue/sdk'

module Schema
  module Extract
    # Every resource of a bridge, for build.rb to learn which fields it always sends. The capture holds the home's
    # data: keep it out of the repository.
    module Capture
      module_function

      def configure(env)
        Hue::Sdk.configure do |config|
          config.host = env.fetch('HUE_HOST')
          config.bridge_id = env.fetch('HUE_BRIDGE_ID')
          config.application_key = env.fetch('HUE_APPLICATION_KEY')
        end
      end

      def write(path) = File.write(path, JSON.pretty_generate(Hue::Sdk::Client.get('/resource')), perm: 0o600)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Schema::Extract::Capture.configure(ENV)
  Schema::Extract::Capture.write(ARGV.fetch(0))
end
