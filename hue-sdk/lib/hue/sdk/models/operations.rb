# frozen_string_literal: true

module Hue
  module Sdk
    module Models
      # Write operations, mixed into a model only when the API accepts them.
      module Operations
        # Lets a collection create resources.
        module Create
          # Creates a resource.
          #
          # @param attributes [Hash] attributes of the new resource
          # @return [Base::Instance] the created resource, loaded lazily
          # @api public
          def create(**attributes)
            created = Client.post(path, body: attributes).first.to_h
            self.class::Instance.new(created.fetch('rid'))
          end
        end

        # Lets an instance update its resource.
        module Update
          # Updates the resource; the next {Base::Instance#data} call reloads it.
          #
          # @param attributes [Hash] attributes to change
          # @return [self]
          # @api public
          def update(**attributes)
            Client.put(path, body: attributes)
            @data = nil
            self
          end
        end

        # Lets an instance delete its resource.
        module Delete
          # Deletes the resource.
          #
          # @return [true]
          # @api public
          def delete
            Client.delete(path)
            true
          end
        end
      end
    end
  end
end
