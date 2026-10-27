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
          # @param request [Schema::Value, nil] the new resource, typed (+Schema::RoomAdd+ for a room…)
          # @param attributes [Hash] the new resource as a hash, or fields added to the request
          # @return [Base::Instance] the created resource, loaded lazily
          # @api public
          def create(request = nil, **attributes)
            created = Client.post(path, body: request ? request.to_body.merge(attributes) : attributes).first.to_h
            self.class::Instance.new(created.fetch('rid'))
          end
        end

        # Lets an instance update its resource.
        module Update
          # Updates the resource; the next {Base::Instance#data} call reloads it.
          #
          # @param request [Schema::Value, nil] the changes, typed (+Schema::LightUpdate+ for a light…)
          # @param attributes [Hash] the changes as a hash, or fields added to the request
          # @return [self]
          # @api public
          def update(request = nil, **attributes)
            Client.put(path, body: request ? request.to_body.merge(attributes) : attributes)
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
