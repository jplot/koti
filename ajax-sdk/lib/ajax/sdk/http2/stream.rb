# frozen_string_literal: true

module Ajax
  module Sdk
    module Http2
      # One HTTP/2 stream. The connection's reader thread routes decoded frames here as events; the
      # caller reads them with {#each_event} until the stream ends, and sends body data with {#write}
      # under the connection's flow control.
      class Stream
        INITIAL_RECV_WINDOW = 65_535
        private_constant :INITIAL_RECV_WINDOW

        # @return [Integer] the stream id
        attr_reader :id
        # @return [StandardError, nil] the error that broke the stream, if any
        attr_reader :error
        # @return [Integer] bytes the peer still lets this stream send
        attr_accessor :send_window

        # @param id [Integer]
        # @param connection [Connection]
        # @param send_window [Integer] the peer's initial window size
        # @api private
        def initialize(id, connection, send_window)
          @id = id
          @connection = connection
          @send_window = send_window
          @events = Thread::Queue.new
          @consumed = 0
          @headers_seen = false
        end

        # @yieldparam event [Array] one of +[:headers, Array]+, +[:data, String]+,
        #   +[:trailers, Array]+ or +[:reset, Integer]+
        # @raise [ConnectionClosed] when the connection drops before the stream ends
        def each_event
          loop do
            event = @events.pop
            break if event == :end
            raise event.fetch(1) if event.first == :error

            yield event
          end
        end

        # @param data [String] body bytes
        # @param end_stream [Boolean] whether this is the last write
        # @return [void]
        def write(data, end_stream: false)
          bytes = data.b
          return @connection.send_data(@id, ''.b, end_stream: true) if bytes.empty?

          offset = 0
          while offset < bytes.bytesize
            size = @connection.reserve(self, bytes.bytesize - offset)
            offset += size
            @connection.send_data(@id, bytes.byteslice(offset - size, size) || ''.b,
                                  end_stream: end_stream && offset >= bytes.bytesize)
          end
        end

        # @return [void] send RST_STREAM CANCEL
        def cancel = @connection.cancel(@id)

        # @api private
        def deliver_headers(headers, end_stream)
          @events << [@headers_seen ? :trailers : :headers, headers]
          @headers_seen = true
          finish if end_stream
        end

        # @api private
        def deliver_data(data, end_stream)
          @events << [:data, data] unless data.empty?
          replenish(data.bytesize)
          finish if end_stream
        end

        # @api private
        def deliver_reset(code)
          @events << [:reset, code]
          finish
        end

        # @api private
        def interrupt(error)
          @error = error
          @events << [:error, error]
        end

        private

        def finish = @events << :end

        def replenish(count)
          @consumed += count
          return if @consumed < INITIAL_RECV_WINDOW / 2

          @connection.window_update(@id, @consumed)
          @consumed = 0
        end
      end
    end
  end
end
