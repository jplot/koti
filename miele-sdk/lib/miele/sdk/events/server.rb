# frozen_string_literal: true

require 'json'
require 'socket'
require 'time'
require 'zlib'

module Miele
  module Sdk
    module Events
      # HTTP endpoint the appliances push their changes to once they know this
      # host as a peer. Every request must be signed by the household key.
      class Server
        CONTENT_TYPE = 'application/vnd.miele.v1+json; charset=utf-8'
        private_constant :CONTENT_TYPE

        REASONS = { 200 => 'OK', 201 => 'Created', 204 => 'No Content', 400 => 'Bad Request',
                    403 => 'Forbidden' }.freeze
        private_constant :REASONS

        SUPERVISION = %r{\A/Devices/\d+/SuperVision/(?<peer>\d+)(?<resource>/.*)\z}
        private_constant :SUPERVISION

        # @param port [Integer] port to listen on, 0 for any
        # @param fab [String] fabrication number this host takes in the household
        # @yieldparam event [Event] each change an appliance pushes, from the thread of its
        #   connection: several pushes run the block at once
        def initialize(port:, fab:, &on_event)
          @port = port
          @fab = fab
          @on_event = on_event
          @connections = ThreadGroup.new
        end

        # @return [Integer] port the server listens on
        # @api public
        def port = @server.addr[1]

        # @return [void]
        # @api public
        def start
          @server = TCPServer.new('0.0.0.0', @port) # steep:ignore UnexpectedPositionalArgument
          @connections.add(Thread.new { accept_loop })
        end

        # @return [void]
        # @api public
        def stop
          @server&.close
          @connections.list.each(&:kill)
        end

        private

        # Connection threads inherit the acceptor's group, which {#stop} ends.
        #
        # @return [void]
        def accept_loop
          loop do
            Thread.new(@server.accept) { serve(it) }
          rescue SystemCallError
            sleep 0.1 # out of file descriptors (EMFILE): wait for connections to close
          end
        rescue IOError
          nil
        end

        # @param socket [TCPSocket]
        # @return [void]
        def serve(socket)
          socket.timeout = Sdk.config.read_timeout
          request = Request.read(socket) or return
          plaintext = request.plaintext or return refuse(socket, request)

          route(socket, request, plaintext)
        rescue Request::Malformed
          reply(socket, 400)
        rescue SystemCallError, IOError
          nil
        ensure
          socket.close
        end

        # @return [void]
        def route(socket, request, plaintext)
          case [request.verb, request.path]
          in ['POST', %r{\A/Subscriptions/?\z}] then subscribe(socket, request, plaintext)
          in ['POST', SUPERVISION] then push(socket, request.path, plaintext)
          in ['GET', String => path] then reply(socket, *Identity.resource(path, @fab))
          else reply(socket, 204)
          end
        end

        # A household request that fails the check is forged, or signed in a way
        # this SDK does not expect: the warning tells the two apart.
        #
        # @return [void]
        def refuse(socket, request)
          if request.household?
            warn "miele-sdk: refused a request from #{socket.remote_address.ip_address} " \
                 "(Host: #{request.headers['host']}): its signature does not match the household key"
          end
          reply(socket, 403)
        end

        # The slot comes from the resource rather than a counter, so that
        # connection threads share no state and a renewed subscription keeps its
        # slot; appliances number theirs from 1 to 63.
        #
        # @return [void]
        def subscribe(socket, request, plaintext)
          slot = (Zlib.crc32(JSON.parse(plaintext)['Resource'].to_s) % 63) + 1
          reply(socket, 201, location: "http://#{request.headers['host']}/Subscriptions/#{slot}/")
        end

        # @return [void]
        def push(socket, path, plaintext)
          reply(socket, 204)
          match = SUPERVISION.match(path) #: MatchData
          content = JSON.parse(plaintext)['Content'].to_h
          @on_event.call(Event.new(fab: match[:peer], resource: match[:resource], content:))
        end

        # @param socket [TCPSocket]
        # @param status [Integer]
        # @param body [String] plaintext, sent signed and encrypted
        # @param location [String, nil] +Location+ header
        # @return [void]
        def reply(socket, status, body = '', location: nil)
          date = Time.now.httpdate
          payload, signature = body.empty? ? ['', nil] : seal(status, date, body)
          head = { 'Date' => date, 'Content-Type' => CONTENT_TYPE, 'Content-Length' => payload.bytesize.to_s,
                   'Connection' => 'close', 'X-Signature' => signature, 'Location' => location }.compact
          socket.write("HTTP/1.1 #{status} #{REASONS.fetch(status)}\r\n",
                       *head.map { |name, value| "#{name}: #{value}\r\n" }, "\r\n", payload)
        end

        # @return [Array(String, String)] ciphertext and its +X-Signature+ header
        def seal(status, date, body)
          group_id, key = Connection.credentials
          padded = Crypto.pad(body)
          signature = Crypto.signature(key:, lines: [status, CONTENT_TYPE, date], body: padded)
          [Crypto.encrypt(key:, signature:, plaintext: padded), Crypto.authorization(group_id:, signature:)]
        end
      end
    end
  end
end
