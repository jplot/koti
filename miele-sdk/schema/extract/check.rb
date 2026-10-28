# frozen_string_literal: true

# Usage: ruby schema/extract/check.rb path/to/il

require_relative '../../lib/miele/sdk'
require_relative 'il'

module Schema
  module Extract
    # Compares each typed value of Miele::Sdk::Schema with the app classes it follows: their keys, which may be null,
    # and whether one gathers the keys it does not declare.
    class Check
      REST = 'Miele.Libraries.ApplianceCommunication.Implementation.ApplianceProtocols.Rest'
      SUPER_VISION = 'Miele.Modules.Conactivity.ApplianceCommunication.Implementation.Dtos'
      CLASSES = {
        'DeviceIdentification' => "#{REST}.DeviceIdentificationDto",
        'DeviceIdentificationLabel' => "#{REST}.DeviceIdentificationLabelDto",
        'XkmIdentificationLabel' => "#{REST}.XkmIdentificationLabelDto",
        'DeviceState' => "#{REST}.DeviceStateDto",
        'SuperVision' => "#{SUPER_VISION}.SuperVisionDto",
        'SuperVisionDevice' => "#{SUPER_VISION}.SuperVisionDeviceDto",
        'Subscription' => 'Miele.Libraries.ApplianceCommunication.RawCommunication.Api.Dtos.SubscriptionDto',
        'ModuleUpdateInfo' => 'Miele.Modules.RemoteUpdate.Repository.Dtos.ModuleUpdate.ModuleUpdateInfoDto'
      }.freeze
      # Keys a typed value takes from another app class, so that the answer may lack them.
      BORROWED = {
        'ModuleUpdateInfo' => {
          'Miele.Modules.Pairing.Dto.Bluetooth.Response.CheckUpdateResponseBodyDto' => ['ReleaseNotes']
        }
      }.freeze

      # @param app [Hash] what {Il.read} returns
      def initialize(app) = @app = app

      # @return [Array<String>] each difference, empty when every typed value matches the app
      def differences = CLASSES.flat_map { |name, app_class| compare(name, app_class) }

      private

      def compare(name, app_class)
        missing = [app_class, *BORROWED.fetch(name, {}).keys].reject { @app.key?(it) }
        return missing.map { "#{name}: no app class #{it}" } if missing.any?

        value = Miele::Sdk::Schema.const_get(name)
        fields = fields(name, app_class)
        keys(name, value, fields) + optionality(name, value, fields) +
          extension(name, value, @app[app_class]['extension'])
      end

      def fields(name, app_class)
        BORROWED.fetch(name, {}).reduce(@app[app_class]['fields']) do |all, (other, keys)|
          @app[other]['fields'].slice(*keys).transform_values { it.merge('nullable' => true) }.merge(all)
        end
      end

      def keys(name, value, fields)
        ours = value.json_keys.except(value.extension_member).values
        (fields.keys - ours).sort.map { "#{name}: the app adds #{it}" } +
          (ours - fields.keys).sort.map { "#{name}: the app drops #{it}" }
      end

      def optionality(name, value, fields)
        value.json_keys.except(value.extension_member).filter_map do |member, key|
          next unless fields.key?(key)

          case [value.optional_members.include?(member), fields[key]['nullable']]
          in [true, false] then "#{name}##{member} is optional, but the app never leaves #{key} null"
          in [false, true] then "#{name}##{member} is required, but the app lets #{key} be null"
          else nil
          end
        end
      end

      def extension(name, value, gathers)
        if value.extension_member && !gathers
          ["#{name}##{value.extension_member} gathers the other keys, but the app class does not"]
        elsif gathers && !value.extension_member
          ["#{name}: the app class gathers the other keys, but no member keeps them"]
        else
          []
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  differences = Schema::Extract::Check.new(Schema::Extract::Il.read(Dir[File.join(ARGV.fetch(0), '*.il')])).differences
  puts differences.empty? ? 'Every typed value matches the app classes it follows.' : differences
  exit differences.empty?
end
