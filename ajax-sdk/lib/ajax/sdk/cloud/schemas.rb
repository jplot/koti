# frozen_string_literal: true

require 'zlib'
require 'google/protobuf'
require 'google/protobuf/descriptor_pb'

module Ajax
  module Sdk
    # Everything that talks to the cloud the official Ajax app uses: the schemas, the session and
    # the named resources built on top of them.
    module Cloud
      # One remote procedure of the Ajax cloud: its gRPC path, call type and the full names of its
      # request and response messages. +type+ is +:unary+, +:client_stream+, +:server_stream+ or +:bidi+.
      Rpc = Data.define(:path, :type, :request, :response)

      # The cloud protobuf schemas and the gRPC method table, extracted from the Ajax app and shipped
      # with the gem. The descriptors are loaded once into google-protobuf's pool, the method table
      # once from its TSV, both lazily and behind a mutex.
      module Schemas
        DIRECTORY = File.expand_path('schemas', __dir__ || '.')
        LOCK = Mutex.new
        private_constant :DIRECTORY, :LOCK

        module_function

        # @return [Google::Protobuf::DescriptorPool] the pool holding every cloud message
        def pool
          LOCK.synchronize { @pool ||= load_pool }
        end

        # @param full_name [String] fully qualified message name, without a leading dot
        # @return [Class] the google-protobuf message class
        # @raise [UnknownMessageError] when no such message is known
        def message(full_name)
          pool.lookup(full_name)&.msgclass || raise(UnknownMessageError, "unknown message #{full_name}")
        end

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

        # Adds every file of the shipped FileDescriptorSet, retrying the ones whose dependencies are
        # not in the pool yet, until no further progress is made.
        def load_pool
          target = Google::Protobuf::DescriptorPool.new
          pending = Google::Protobuf::FileDescriptorSet.decode(descriptor_bytes).file.to_a
          loop do
            added = pending.reject! { |file| add_file(target, file) }
            break if pending.empty? || added.nil?
          end
          target
        end

        def add_file(pool, file)
          pool.add_serialized_file(file.to_proto)
          true
        rescue StandardError
          false
        end

        def descriptor_bytes = Zlib.gunzip(File.binread(File.join(DIRECTORY, 'descriptors.pb.gz')))

        def load_rpcs
          File.readlines(File.join(DIRECTORY, 'methods.tsv'), chomp: true).to_h do |line|
            path, type, request, response = line.split("\t")
            rpc = Rpc.new(path: path.to_s, type: type.to_s.to_sym, request: request.to_s, response: response.to_s)
            [rpc.path, rpc]
          end
        end

        private_class_method :load_pool, :add_file, :descriptor_bytes, :load_rpcs
      end
    end
  end
end
