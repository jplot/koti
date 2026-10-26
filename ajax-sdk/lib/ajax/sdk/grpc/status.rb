# frozen_string_literal: true

module Ajax
  module Sdk
    # gRPC calls over the HTTP/2 connection: the four call kinds and the status trailers.
    module Grpc
      # A non-OK gRPC status. +code+ is the numeric status and +details+ the decoded grpc-message.
      class Error < ::Ajax::Sdk::Error
        # @return [Integer] the gRPC status code
        attr_reader :code
        # @return [String] the human-readable grpc-message
        attr_reader :details

        # @param code [Integer]
        # @param details [String]
        def initialize(code, details)
          @code = code
          @details = details
          super("gRPC status #{code}: #{details}")
        end
      end

      # The request was not authenticated (status 16).
      class Unauthenticated < Error; end
      # The caller lacks permission (status 7).
      class PermissionDenied < Error; end
      # The resource was not found (status 5).
      class NotFound < Error; end
      # The service is unavailable, including on a dropped connection (status 14).
      class Unavailable < Error; end
      # The deadline passed before the call finished (status 4).
      class DeadlineExceeded < Error; end

      # A gRPC frame broke the protocol, such as a compressed message this client cannot read.
      class ProtocolError < ::Ajax::Sdk::Error; end

      # Reads the gRPC status out of a header or trailer list and raises the matching error.
      module Status
        CLASSES = {
          4 => DeadlineExceeded, 5 => NotFound, 7 => PermissionDenied, 14 => Unavailable, 16 => Unauthenticated
        }.freeze
        private_constant :CLASSES

        module_function

        # @param pairs [Array<Array(String, String)>] the response's headers or trailers
        # @return [void]
        # @raise [Error] when a grpc-status header is present and non-zero
        def check(pairs)
          code = find(pairs, 'grpc-status')
          return if code.nil? || code == '0'

          number = code.to_i
          raise CLASSES.fetch(number, Error).new(number, percent_decode(find(pairs, 'grpc-message').to_s))
        end

        # @return [String, nil] the value of +name+ in +pairs+, if present
        def find(pairs, name) = pairs.find { |key, _value| key == name }&.last

        # @param text [String] a grpc-message, percent-encoded per the gRPC spec
        # @return [String] the decoded UTF-8 text
        def percent_decode(text)
          text.gsub(/%([0-9A-Fa-f]{2})/) { Regexp.last_match(1).to_s.to_i(16).chr }.force_encoding(Encoding::UTF_8)
        end
      end
    end
  end
end
