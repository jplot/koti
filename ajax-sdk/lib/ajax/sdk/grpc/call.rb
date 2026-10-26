# frozen_string_literal: true

require_relative 'status'
require_relative '../version'

module Ajax
  module Sdk
    module Grpc
      # Splits a gRPC data stream into messages: each is a 5-byte prefix (1 flag byte, then the
      # length as a big-endian uint32) followed by the message bytes. A set flag means compression,
      # which this client does not support.
      class MessageReader
        def initialize
          @buffer = +''.b
        end

        # @param data [String] more bytes from the stream
        # @return [Array<String>] the messages that are now complete
        # @raise [ProtocolError] on a compressed message
        def push(data) # rubocop:disable Metrics/AbcSize -- one gRPC length-prefix parse loop
          @buffer << data
          messages = [] #: Array[String]
          while @buffer.bytesize >= 5
            length = (@buffer.byteslice(1, 4) || ''.b).unpack1('N').to_i
            break if @buffer.bytesize < 5 + length
            raise ProtocolError, 'a compressed gRPC message is not supported' unless @buffer.getbyte(0).to_i.zero?

            messages << (@buffer.byteslice(5, length) || ''.b)
            @buffer = @buffer.byteslice((5 + length)..) || +''.b
          end
          messages
        end
      end

      # A full-duplex bidi call: send requests, close the sending half, and iterate the responses.
      class BidiCall
        # @api private
        def initialize(channel, path, stream)
          @channel = channel
          @path = path
          @stream = stream
        end

        # @param request [Hash] the request message
        # @return [BidiCall] self, so sends can chain
        def send(request)
          @stream.write(@channel.frame(@path, request))
          self
        end

        # @return [void] half-close the stream: no more requests will be sent
        def close_send = @stream.write(''.b, end_stream: true)

        # @yieldparam message [Hash] each decoded response
        def each(&) = @channel.consume(@path, @stream, &)
      end

      # Makes gRPC calls of all four kinds over an {Http2::Connection}, framing requests and decoding
      # responses with a {Protobuf::Codec} and a registry that maps a path to its request and response.
      class Channel
        USER_AGENT = "ajax-sdk/#{Ajax::Sdk::VERSION}".freeze
        private_constant :USER_AGENT

        # @param connection [Http2::Connection]
        # @param authority [String] the +:authority+ header
        # @param codec [Protobuf::Codec]
        # @param registry [#rpc] resolves a path to an Rpc with request and response message names
        def initialize(connection, authority:, codec:, registry:)
          @connection = connection
          @authority = authority
          @codec = codec
          @registry = registry
        end

        # @return [Array<Array(String, String)>, nil] the last call's response headers
        attr_reader :response_headers

        # @return [Hash] the single response message
        def unary(path, request, metadata: [], deadline: nil)
          stream = start(path, metadata, deadline)
          stream.write(frame(path, request), end_stream: true)
          first(path, stream)
        end

        # @yieldparam message [Hash] each response message
        def server_stream(path, request, metadata: [], &)
          stream = start(path, metadata, nil)
          stream.write(frame(path, request), end_stream: true)
          consume(path, stream, &)
        end

        # @param requests [Array<Hash>] the request messages
        # @return [Hash] the single response message
        def client_stream(path, requests, metadata: [])
          stream = start(path, metadata, nil)
          requests.each_with_index do |request, index|
            stream.write(frame(path, request), end_stream: index == requests.size - 1)
          end
          first(path, stream)
        end

        # @yieldparam call [BidiCall]
        def bidi(path, metadata: [])
          yield BidiCall.new(self, path, start(path, metadata, nil))
        end

        # @api private
        def frame(path, request)
          body = @codec.encode(@registry.rpc(path).request, request)
          [0, body.bytesize].pack('CN') + body
        end

        # @api private
        def consume(path, stream, &)
          reader = MessageReader.new
          trailers = read_events(stream, reader, path, &)
          Status.check(trailers || @response_headers || [])
        end

        private

        def read_events(stream, reader, path) # rubocop:disable Metrics/MethodLength -- one event dispatch loop
          trailers = nil
          stream.each_event do |type, value|
            case type
            when :headers then @response_headers = value
            when :data then reader.push(value).each { |bytes| yield decode(path, bytes) }
            when :trailers then trailers = value
            when :reset then raise Unavailable.new(14, "stream reset with code #{value}")
            end
          end
          trailers
        rescue Http2::ConnectionClosed => e
          raise Unavailable.new(14, e.message)
        end

        def first(path, stream)
          message = nil #: Hash[Symbol, untyped]?
          consume(path, stream) { |decoded| message ||= decoded }
          message
        end

        def start(path, metadata, deadline)
          @connection.request(headers(path, metadata, deadline), end_stream: false)
        end

        def headers(path, metadata, deadline)
          pairs = pseudo(path)
          pairs << ['grpc-timeout', "#{(deadline * 1000).to_i}m"] if deadline
          pairs.concat(metadata)
        end

        def pseudo(path)
          [[':method', 'POST'], [':scheme', 'https'], [':path', path], [':authority', @authority],
           ['content-type', 'application/grpc'], ['te', 'trailers'], ['user-agent', USER_AGENT]]
        end

        def decode(path, bytes) = @codec.decode(@registry.rpc(path).response, bytes)
      end
    end
  end
end
