# frozen_string_literal: true

# Usage: MIELE_GROUP_ID=… MIELE_GROUP_KEY=… MIELE_HOSTS=host,… ruby schema/extract/capture.rb CAPTURE

require 'json'
require_relative '../../lib/miele/sdk'

module Schema
  module Extract
    # Every JSON resource of the appliances, for match.rb to find the app classes that read them. The capture holds the
    # home's data: keep it out of the repository.
    module Capture
      DEVICE = ['', 'Ident', 'State', 'Settings', 'Service', 'Update', 'SuperVision'].freeze
      MODULE = %w[/ /Info /Host /Update/ /Subscriptions/].freeze

      module_function

      def configure(env)
        Miele::Sdk.configure do |config|
          config.group_id = env.fetch('MIELE_GROUP_ID')
          config.group_key = env.fetch('MIELE_GROUP_KEY')
        end
      end

      def read(hosts) = hosts.to_h { [it, appliance(Miele::Sdk.appliance(it))] }

      def write(path, hosts)
        File.open(path, 'w', 0o600) do |file|
          file.chmod(0o600)
          file.write(JSON.pretty_generate(read(hosts)))
        end
      end

      # An appliance may refuse every request: the oven answered 503 all morning on 2026-10-28.
      def appliance(appliance)
        fab = appliance.fab
        paths = ['/Devices/', *DEVICE.map { "/Devices/#{fab}/#{it}" }, *MODULE]
        paths.to_h { [it.sub(fab, '{fab}'), resource(appliance, it)] }
      rescue Miele::Sdk::Error => e
        { 'error' => e.class.name }
      end

      def resource(appliance, path)
        appliance.get(path)
      rescue Miele::Sdk::Error => e
        { 'error' => e.class.name }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Schema::Extract::Capture.configure(ENV)
  Schema::Extract::Capture.write(ARGV.fetch(0), ENV.fetch('MIELE_HOSTS').split(','))
end
