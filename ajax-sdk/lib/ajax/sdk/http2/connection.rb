# frozen_string_literal: true

require 'socket'
require 'openssl'
require_relative 'frame'
require_relative 'hpack'
require_relative 'stream'

module Ajax
  module Sdk
    module Http2
      # The HTTP/2 connection preface, sent before the client's first SETTINGS frame.
      PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".b

      # A client HTTP/2 connection over TLS (ALPN +h2+). One reader thread dispatches incoming frames
      # to their streams, answers PING, applies the peer's SETTINGS and tracks flow-control windows;
      # callers open streams with {#request} and send body data with {Stream#write}.
      class Connection # rubocop:disable Metrics/ClassLength -- a self-contained HTTP/2 client
        include Frames

        DEFAULT_MAX_FRAME = 16_384
        DEFAULT_WINDOW = 65_535
        SETTING_INITIAL_WINDOW = 4
        SETTING_MAX_FRAME = 5
        CANCEL = 0x8

        private_constant :DEFAULT_MAX_FRAME, :DEFAULT_WINDOW, :SETTING_INITIAL_WINDOW, :SETTING_MAX_FRAME, :CANCEL

        # @return [Integer] the largest DATA payload the peer accepts
        attr_reader :max_frame_size

        # @param host [String]
        # @param port [Integer]
        # @param ca_file [String, nil] a PEM bundle to trust on top of the system store
        # @param open_timeout [Numeric] seconds to wait for the TCP connect
        # @return [Connection]
        # @raise [ProtocolError] when the server does not select h2
        def self.open(host:, port:, ca_file: nil, open_timeout: 10)
          new(connect(host, port, ca_file, open_timeout))
        end

        # @param io [IO] a socket already carrying an h2 connection (TLS or, in specs, plain TCP)
        def initialize(io) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength -- wires up all the connection state
          @io = io
          @streams = {}
          @streams_mutex = Mutex.new
          @flow_mutex = Mutex.new
          @flow_cv = ConditionVariable.new
          @write_mutex = Mutex.new
          @encoder = Hpack::Encoder.new
          @decoder = Hpack::Decoder.new
          @max_frame_size = DEFAULT_MAX_FRAME
          @conn_send_window = DEFAULT_WINDOW
          @peer_initial_window = DEFAULT_WINDOW
          @recv_consumed = 0
          @next_id = 1
          @closed = nil
          @settings = Thread::Queue.new
          handshake
          @reader = Thread.new { read_loop }
          @settings.pop
        end

        # @param headers [Array<Array(String, String)>] the request pseudo- and regular headers
        # @param end_stream [Boolean] whether the request has no body
        # @return [Stream]
        def request(headers, end_stream: false)
          @write_mutex.synchronize do
            id = @next_id
            @next_id += 2
            stream = Stream.new(id, self, @peer_initial_window)
            @streams_mutex.synchronize { @streams[id] = stream }
            flags = END_HEADERS | (end_stream ? END_STREAM : 0)
            @io.write(Frame.new(type: HEADERS, flags:, stream_id: id, payload: @encoder.encode(headers)).to_s)
            stream
          end
        end

        # @return [void] send GOAWAY, close the socket and join the reader thread
        def close
          write_frame(Frame.new(type: GOAWAY, flags: 0, stream_id: 0, payload: [0, 0].pack('NN')))
          @io.close
        rescue IOError
          nil
        ensure
          @reader.kill
          @reader.join
        end

        # @api private
        def reserve(stream, want) # rubocop:disable Metrics/MethodLength -- one flow-control wait loop
          @flow_mutex.synchronize do
            loop do
              error = stream.error || @closed
              raise error if error

              size = [stream.send_window, @conn_send_window, @max_frame_size, want].min
              if size.positive?
                stream.send_window -= size
                @conn_send_window -= size
                return size
              end
              @flow_cv.wait(@flow_mutex)
            end
          end
        end

        # @api private
        def send_data(id, data, end_stream:)
          write_frame(Frame.new(type: DATA, flags: end_stream ? END_STREAM : 0, stream_id: id, payload: data))
        end

        # @api private
        def window_update(id, increment)
          write_frame(Frame.new(type: WINDOW_UPDATE, flags: 0, stream_id: id, payload: [increment].pack('N')))
        end

        # @api private
        def cancel(id)
          forget(id)
          write_frame(Frame.new(type: RST_STREAM, flags: 0, stream_id: id, payload: [CANCEL].pack('N')))
        end

        def self.connect(host, port, ca_file, open_timeout) # rubocop:disable Metrics/MethodLength -- one TLS setup
          tcp = Socket.tcp(host, port, connect_timeout: open_timeout)
          context = OpenSSL::SSL::SSLContext.new
          context.alpn_protocols = ['h2']
          context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, **(ca_file ? { ca_file: } : {}))
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
          ssl.hostname = host
          ssl.sync_close = true
          ssl.connect
          ssl.post_connection_check(host)
          raise ProtocolError, 'server did not select h2' unless ssl.alpn_protocol == 'h2'

          ssl
        end

        private

        def handshake
          @io.write(PREFACE)
          @io.write(Frame.new(type: SETTINGS, flags: 0, stream_id: 0, payload: ''.b).to_s)
        end

        def write_frame(frame)
          @write_mutex.synchronize { @io.write(frame.to_s) }
        rescue IOError
          nil
        end

        def read_loop
          loop { handle(Frame.read(@io)) }
        rescue IOError, OpenSSL::SSL::SSLError
          shutdown(ConnectionClosed.new('the connection closed'))
        end

        def handle(frame) # rubocop:disable Metrics/CyclomaticComplexity -- one frame-type dispatch
          case frame.type
          when SETTINGS then on_settings(frame)
          when PING then on_ping(frame)
          when GOAWAY then on_goaway(frame)
          when WINDOW_UPDATE then on_window_update(frame)
          when HEADERS then on_headers(frame)
          when DATA then on_data(frame)
          when RST_STREAM then on_rst(frame)
          end
        end

        def on_settings(frame)
          return if frame.flag?(ACK)

          frame.payload.unpack('nN' * (frame.payload.bytesize / 6)).each_slice(2) do |id, value|
            apply_setting(Integer(id), Integer(value))
          end
          write_frame(Frame.new(type: SETTINGS, flags: ACK, stream_id: 0, payload: ''.b))
          @settings.close
        end

        def apply_setting(id, value)
          case id
          when SETTING_MAX_FRAME then @max_frame_size = value
          when SETTING_INITIAL_WINDOW then grow_windows(value)
          end
        end

        def grow_windows(value)
          @flow_mutex.synchronize do
            delta = value - @peer_initial_window
            @peer_initial_window = value
            @streams_mutex.synchronize { @streams.each_value { |stream| stream.send_window += delta } }
            @flow_cv.broadcast
          end
        end

        def on_ping(frame)
          return if frame.flag?(ACK)

          write_frame(Frame.new(type: PING, flags: ACK, stream_id: 0, payload: frame.payload))
        end

        def on_goaway(frame)
          last = frame.payload.unpack1('N').to_i & 0x7FFFFFFF
          @streams_mutex.synchronize do
            @streams.each { |id, stream| stream.interrupt(ConnectionClosed.new('GOAWAY')) if id > last }
            @streams.reject! { |id, _stream| id > last }
          end
          @flow_mutex.synchronize { @flow_cv.broadcast }
        end

        def on_window_update(frame)
          increment = frame.payload.unpack1('N').to_i & 0x7FFFFFFF
          stream = lookup(frame.stream_id) unless frame.stream_id.zero?
          @flow_mutex.synchronize do
            if frame.stream_id.zero?
              @conn_send_window += increment
            elsif stream
              stream.send_window += increment
            end
            @flow_cv.broadcast
          end
        end

        def on_headers(frame)
          payload = +frame.payload
          last = frame
          until last.flag?(END_HEADERS)
            last = Frame.read(@io)
            payload << last.payload
          end
          lookup(frame.stream_id)&.deliver_headers(@decoder.decode(payload), frame.flag?(END_STREAM))
          forget(frame.stream_id) if frame.flag?(END_STREAM)
        end

        def on_data(frame)
          lookup(frame.stream_id)&.deliver_data(frame.payload, frame.flag?(END_STREAM))
          forget(frame.stream_id) if frame.flag?(END_STREAM)
          replenish_connection(frame.payload.bytesize)
        end

        def on_rst(frame)
          lookup(frame.stream_id)&.deliver_reset(frame.payload.unpack1('N').to_i)
          forget(frame.stream_id)
        end

        def replenish_connection(count)
          @recv_consumed += count
          return if @recv_consumed < DEFAULT_WINDOW / 2

          window_update(0, @recv_consumed)
          @recv_consumed = 0
        end

        def lookup(id) = @streams_mutex.synchronize { @streams[id] }
        def forget(id) = @streams_mutex.synchronize { @streams.delete(id) }

        def shutdown(error)
          @closed = error
          @streams_mutex.synchronize do
            @streams.each_value { |stream| stream.interrupt(error) }
            @streams.clear
          end
          @flow_mutex.synchronize { @flow_cv.broadcast }
        end
      end
    end
  end
end
