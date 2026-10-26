# frozen_string_literal: true

require 'zlib'

module Ajax
  module Sdk
    # Everything that talks to the cloud the official Ajax app uses: the schemas, the gRPC
    # method table, the session and the named resources built on top of them.
    module Cloud
      # One remote procedure of the Ajax cloud: its gRPC path, call type and the full names of its
      # request and response messages. +type+ is +:unary+, +:client_stream+, +:server_stream+ or +:bidi+.
      Rpc = Data.define(:path, :type, :request, :response)

      # The cloud protobuf schemas and the gRPC method table, extracted from the Ajax app and shipped
      # with the gem. Both are read once, lazily, behind a mutex, so the first caller pays for loading
      # and every later one shares it.
      module Schemas
        # Directory of the shipped +descriptors.pb.gz+ and +methods.tsv+.
        DIRECTORY = File.expand_path('schemas', __dir__ || '.')
        # Guards the one-time load of the registry and the method table.
        LOCK = Mutex.new

        module_function

        # @return [Protobuf::Registry] every message and enum of the cloud protocol
        def registry
          LOCK.synchronize { @registry ||= Protobuf::Registry.from_descriptor_set(descriptor_bytes) }
        end

        # @param full_name [String] fully qualified message name, without a leading dot
        # @return [Protobuf::Message]
        # @raise [ArgumentError] when no such message is known
        def message(full_name) = registry.message(full_name)

        # @param full_name [String] fully qualified enum name, without a leading dot
        # @return [Protobuf::Enum]
        # @raise [ArgumentError] when no such enum is known
        def enum(full_name) = registry.enum(full_name)

        # @param path [String] a gRPC path, +/<service>/<method>+
        # @return [Rpc]
        # @raise [UnknownMethodError] when the path is not in the method table
        def rpc(path)
          rpcs.fetch(path) { raise UnknownMethodError, "unknown method #{path}" }
        end

        # @return [Hash{String=>Rpc}] the whole method table, keyed by gRPC path
        def rpcs
          LOCK.synchronize { @rpcs ||= load_rpcs }
        end

        def descriptor_bytes = Zlib.gunzip(File.binread(File.join(DIRECTORY, 'descriptors.pb.gz')))

        def load_rpcs
          File.readlines(File.join(DIRECTORY, 'methods.tsv'), chomp: true).to_h do |line|
            path, type, request, response = line.split("\t")
            rpc = Rpc.new(path: path.to_s, type: type.to_s.to_sym, request: request.to_s, response: response.to_s)
            [rpc.path, rpc]
          end
        end

        private_class_method :descriptor_bytes, :load_rpcs
      end
    end
  end
end
