# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    # Typed values of the JSON the appliances and their Wi-Fi modules serve, after the classes the Miele
    # app 4.19.0 reads and writes it with. A member is optional where the app's class lets it be null.
    module Schema
      # Behavior of every value class.
      module Value
        # @param base [Class]
        # @return [void]
        # @api private
        def self.included(base) = base.extend(ClassMethods)

        # Class methods of the value classes.
        module ClassMethods
          # @return [Symbol, nil] the member holding the keys no other member reads
          # @api private
          attr_reader :extension_member

          # @return [Array<Symbol>] the members a value may leave out
          # @api private
          def optional_members = @optional_members || []

          # @return [Hash{Symbol=>Class}] the members holding a value
          # @api private
          def nested_members = @nested_members || {}

          # @return [Hash{Symbol=>String}] the JSON key of each member: the member in PascalCase, unless the
          #   class spells it otherwise
          # @api public
          def json_keys = members.to_h { [it, (@keys || {}).fetch(it) { it.to_s.split('_').map(&:capitalize).join }] }

          # Builds a value from the JSON of an appliance. The keys its class does not know are dropped, or
          # kept in its extension member.
          #
          # @param data [Hash{String=>Object}]
          # @return [Value]
          # @api public
          def from(data)
            fields = json_keys.to_h do |member, key|
              type = nested_members[member]
              [member, type && data[key] ? type.from(data[key]) : data[key]]
            end #: Hash[Symbol, untyped]
            fields[extension_member] = data.except(*json_keys.values) if extension_member
            new(**fields)
          end

          # @param fields [Hash{Symbol=>Object}] the members of a value
          # @return [Hash{String=>Object}] the members not nil under their JSON keys, the extension's spread
          # @api private
          def body(fields)
            keyed = fields.except(extension_member).compact.to_h do |name, field|
              [json_keys.fetch(name), field.is_a?(Value) ? field.to_body : field]
            end
            extension_member ? keyed.merge(fields.fetch(extension_member)) : keyed
          end

          private

          # @param names [Array<Symbol>]
          # @return [void]
          # @api private
          def optional(*names) = @optional_members = names

          # @param types [Hash{Symbol=>Class}]
          # @return [void]
          # @api private
          def nested(**types) = @nested_members = types

          # @param names [Hash{Symbol=>String}] the JSON key of the members not spelt in PascalCase
          # @return [void]
          # @api private
          def keys(**names) = @keys = names

          # @param name [Symbol] the member taking the keys no other member reads, as the app's
          #   +JsonExtensionData+ does
          # @return [void]
          # @api private
          def extension(name) = @extension_member = name
        end

        # @param fields [Hash{Symbol=>Object}] the members; an optional one left out is nil
        # @raise [ArgumentError] for an unknown member, or a missing one the class requires
        # @api public
        def initialize(**fields)
          value_class = self.class #: ClassMethods
          super(**value_class.optional_members.to_h { [it, nil] }, **fields)
        end

        # @return [Hash{String=>Object}] the value as a JSON body under the keys of the appliance, without its
        #   nil members
        # @raise [ArgumentError] if a member the class requires is nil
        # @api public
        def to_body
          value_class = self.class #: ClassMethods
          missing = to_h.filter_map { |name, field| name if field.nil? } - value_class.optional_members
          raise ArgumentError, "required field left nil: #{missing.join(', ')}" if missing.any?

          value_class.body(to_h)
        end

        # @param state [JSON::State, nil] the state of the JSON generator
        # @return [String] the JSON of {#to_body}
        # @api public
        def to_json(state = nil) = to_body.to_json(state)
      end
    end
  end
end

require_relative 'schema/ident'
require_relative 'schema/state'
require_relative 'schema/super_vision'
require_relative 'schema/subscription'
require_relative 'schema/update'
