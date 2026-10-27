# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Collection of one resource type: lists its resources and, when the API
      # allows it, creates them.
      #
      # @abstract Subclass, then declare {.resource_type} and {.operations}.
      class Base
        # One resource, loaded lazily.
        class Instance
          class << self
            # @return [Class] the collection model this instance class belongs to
            # @api private
            attr_accessor :model
          end

          # @return [String] resource id
          attr_reader :id

          # @param id [String] resource id
          # @param data [Hash{String=>Object}, nil] data already loaded
          # @api public
          def initialize(id, data: nil)
            @id = id
            @data = data && visible(data)
          end

          # @return [Hash{String=>Object}] the resource, fetched on first access
          # @api public
          def data = @data ||= visible(Client.get(path).first.to_h)

          # @param key [String, Symbol] attribute name
          # @return [Object, nil] one attribute of {#data}
          # @api public
          def [](key) = data[key.to_s]

          # @return [Instance, nil] the resource owning this one (a device for a light service)
          # @api public
          def owner = data['owner']&.then { reference(it) }

          # @return [Array<Instance>] the resources grouped by this one (a room's devices)
          # @api public
          def children = data.fetch('children', []).map { reference(it) }

          # @return [Array<Instance>] the services of this resource (a device's light, motion…)
          # @api public
          def services = data.fetch('services', []).map { reference(it) }

          private

          # @return [String]
          # @api private
          def path = "/resource/#{self.class.model.type}/#{id}"

          # @param target [Hash{String=>String}] a +{rid, rtype}+ reference
          # @return [Instance]
          # @api private
          def reference(target) = Sdk.resource(target['rtype'], target['rid'])

          # @param data [Hash{String=>Object}]
          # @return [Hash{String=>Object}] data without the deprecated fields of the model
          # @api private
          def visible(data) = self.class.model.strip(data)
        end

        class << self
          # @return [String] the CLIP v2 resource type of this model
          # @api public
          attr_reader :type

          # @return [Array<String>] deprecated fields removed from the data, nested ones as +attribute.field+
          # @api private
          def hidden_fields = @hidden_fields || []

          # @param data [Hash{String=>Object}] a resource, or the changes of an event
          # @return [Hash{String=>Object}] +data+ without the deprecated fields of the model
          # @api private
          def strip(data) = hidden_fields.reduce(data) { |visible, path| without(visible, *path.split('.')) }

          private

          # @param data [Hash{String=>Object}]
          # @param key [String]
          # @param nested [Array<String>] the rest of the path under +key+
          # @return [Hash{String=>Object}] a copy of +data+ without the field at the path
          # @api private
          def without(data, key, *nested)
            return data.except(key) if nested.empty?
            return data unless data[key].is_a?(Hash)

            data.merge(key => without(data[key], *nested))
          end

          # Binds the model to a resource type, registers it and gives its instances their typed value.
          #
          # @param type [String]
          # @return [void]
          # @api private
          def resource_type(type)
            @type = type
            REGISTRY[type] = self
            self::Instance.include(Typed)
          end

          # Mixes in the write operations the API accepts for this type.
          #
          # @param names [Array<Symbol>] among +:create+, +:update+ and +:delete+
          # @return [void]
          # @api private
          def operations(*names)
            include Operations::Create if names.include?(:create)
            self::Instance.include(Operations::Update) if names.include?(:update)
            self::Instance.include(Operations::Delete) if names.include?(:delete)
          end

          # @param fields [Array<String>] fields superseded by newer ones, nested ones as +attribute.field+
          # @return [void]
          # @api private
          def deprecated(*fields)
            @hidden_fields = fields
          end

          # Gives each model its own instance class, bound back to the model.
          #
          # @param model [Class]
          # @return [void]
          # @api private
          def inherited(model)
            super
            instance_class = Class.new(self::Instance) #: singleton(Instance)
            model.const_set(:Instance, instance_class).model = model
          end
        end

        # @return [Array<Instance>] every resource of this type, data preloaded
        # @api public
        def list = Client.get(path).map { self.class::Instance.new(it['id'], data: it) }

        private

        # @return [String]
        # @api private
        def path = "/resource/#{self.class.type}"
      end
    end
  end
end
