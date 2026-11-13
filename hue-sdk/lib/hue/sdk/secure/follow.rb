# frozen_string_literal: true

require 'json'
require 'openssl'
require 'securerandom'
require 'timeout'

module Hue
  module Sdk
    module Secure
      # Follows a home over the MQTT broker of Hue Secure, as the app's +BaseHomeMqttClient+ does: TLS with ALPN
      # +mqtt+ to the one root the app pins, MQTT 3.1.1, the token in the username of AWS IoT's custom authorizer.
      # It reads once and never publishes. Never tested on a device.
      class Follow
        include Enumerable

        # The topics the app follows and reads, under +dt:home/<home>/+.
        TOPICS = %w[arm/state arm/config arm/schedules device/+/config timeline/update].freeze

        NETWORK_ERRORS = [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError].freeze
        private_constant :NETWORK_ERRORS

        AUTHORIZER = 'app?x-amz-customauthorizer-name=mqtt-app-authorizer&token='
        private_constant :AUTHORIZER

        # What the mqtt gem raises when the broker ends the connection before a byte it waits for.
        ENDED = 'Failed to read byte from socket'

        # The mqtt gem's words for CONNACK 4 and 5.
        REFUSED = /bad user name or password|not authori[sz]ed/
        private_constant :ENDED, :REFUSED

        # One message of the broker.
        #
        # @!attribute [r] topic
        #   @return [String] the topic under +dt:home/<home>/+, such as +arm/state+
        # @!attribute [r] payload
        #   @return [String] the JSON the broker sent
        Message = Data.define(:topic, :payload)

        # One message of the broker, read as the app reads its topic.
        class Message
          # @return [Sdk::Schema::Value, Array<Sdk::Schema::Value>, MessageEvent, nil] the payload read as the app
          #   reads its topic; nil for a topic the app does not read, the +null+ the app skips, or a payload the gem
          #   cannot read
          # @api public
          def attributes
            data = JSON.parse(payload)
            data && Follow.read(topic, data)
          rescue JSON::ParserError, TypeError
            nil
          end
        end

        # @param topic [String]
        # @param data [Object] the parsed payload
        # @return [Object, nil]
        # @api private
        def self.read(topic, data)
          case topic
          when 'arm/state' then Sdk::Schema::Value.load(Schema::ArmDisarmStateResponse, data)
          when 'arm/config' then Sdk::Schema::Value.load(Schema::ArmDisarmConfigResponse, data)
          when 'arm/schedules' then Sdk::Schema::Value.load([Schema::ArmDisarmScheduleResponse], data)
          when %r{\Adevice/[^/]+/config\z} then Sdk::Schema::Value.load(Schema::CameraConfigUpdateEventValues, data)
          when 'timeline/update' then MessageEvent.from(Sdk::Schema::Value.shaped(Hash, data))
          end
        end

        # @param home_id [String]
        # @param topics [Array<String>]
        # @param keep_alive [Numeric] seconds between two packets the client sends at most, the app's 60
        # @api public
        def initialize(home_id, topics:, keep_alive: 60)
          @prefix = "dt:home/#{home_id}/"
          @topics = topics
          @keep_alive = keep_alive
        end

        # Follows the home until the broker ends the connection; the caller decides whether to follow it again. An
        # error the block raises goes through as it is.
        #
        # @yieldparam message [Message]
        # @return [void]
        # @raise [Error] without the mqtt gem
        # @raise [AuthenticationError] if the broker refuses the token
        # @raise [TLSError] if the broker's certificate does not chain to the pinned root, or names another host
        # @raise [ConnectionError] if the broker cannot be reached, drops the connection, or leaves a ping unanswered
        # @api public
        def each(&)
          begin
            require 'mqtt'
          rescue LoadError
            raise Error, "following a Hue Secure home needs the mqtt gem: add gem 'mqtt' to your Gemfile"
          end
          follow(&)
        end

        private

        # The gem's reader thread raises why the connection ended into the thread that connected, wherever it is: a
        # thread of the SDK connects and relays the messages, so that the caller's thread never gets it.
        #
        # @yieldparam message [Message]
        # @return [void]
        def follow(&)
          client = mqtt_client(Secure.config, "#{AUTHORIZER}#{Secure.session.current.value}")
          relayed = Thread::Queue.new
          relay = Thread.new { watch(client, relayed) }
          relaying(relayed, &)
        ensure
          relay&.kill&.join
          hang_up(client) if client
        end

        # @param relayed [Thread::Queue]
        # @yieldparam message [Message]
        # @return [void]
        def relaying(relayed)
          while (packet = relayed.pop).is_a?(MQTT::Packet::Publish)
            yield message(packet)
          end
          raise translated(packet) unless packet.message == ENDED
        end

        # @param client [MQTT::Client]
        # @param relayed [Thread::Queue] where the messages go, then why the connection ended or could not be made
        # @return [void]
        def watch(client, relayed)
          connect(client)
          Thread.handle_interrupt(Exception => :never) { relayed << receive(client, relayed) }
        rescue Exception => e # rubocop:disable Lint/RescueException -- the following thread raises it, or ends on it
          relayed << e
        end

        # Why the connection ended gets in only while this thread waits for a message, so that none the gem read is
        # lost; what is still queued then goes on, without the acknowledgement the socket can no longer carry.
        #
        # @param client [MQTT::Client]
        # @param relayed [Thread::Queue]
        # @return [Exception] why the connection ended
        def receive(client, relayed)
          client.subscribe(@topics.to_h { ["#{@prefix}#{it}", 1] })
          Thread.handle_interrupt(Exception => :on_blocking) { client.get_packet { relayed << it } }
        rescue Exception => e # rubocop:disable Lint/RescueException -- what the reader thread raised, or a failed write
          e = awaited if e.is_a?(MQTT::NotConnectedException) || client.connected?
          relayed << client.get_packet { break it } until client.queue_empty?
          e
        end

        # An acknowledgement fails once the reader thread has closed the socket, or once the broker is gone before the
        # reader sees it (2 follows in 2000 on 2026-11-08): why the connection ended still comes from the reader.
        #
        # @return [Exception] why the connection ended
        def awaited
          Thread.handle_interrupt(Exception => :immediate) { loop { sleep } }
        rescue Exception => e # rubocop:disable Lint/RescueException -- why the connection ended, whatever its class
          e
        end

        # The gem bounds the TCP connection and the CONNACK, not the TLS handshake between them.
        #
        # @param client [MQTT::Client]
        # @return [void]
        def connect(client)
          config = Secure.config
          limit = config.open_timeout.to_f + config.read_timeout
          Timeout.timeout(limit, ConnectionError, "#{config.mqtt_host}: connecting took too long") { client.connect }
        rescue StandardError, MQTT::Exception => e
          client.disconnect(false)
          raise translated(e)
        end

        # The gem writes DISCONNECT before it closes the socket, and that write fails once the broker is gone.
        #
        # @param client [MQTT::Client]
        # @return [void]
        def hang_up(client)
          client.disconnect
        rescue MQTT::Exception, *NETWORK_ERRORS
          client.disconnect(false)
        end

        # @param config [Configuration::Settings]
        # @param username [String] the token, in the username of the authorizer
        # @return [MQTT::Client] as the app sets its own up: TLS with ALPN +mqtt+ to the pinned root alone, MQTT 3.1.1,
        #   the gem's own client id
        def mqtt_client(config, username)
          MQTT::Client.new(host: config.mqtt_host, port: config.mqtt_port, ssl: true, keep_alive: @keep_alive,
                           client_id: "hue-sdk:#{SecureRandom.uuid}", username:, connect_timeout: config.open_timeout,
                           ack_timeout: config.read_timeout).tap do |client|
            client.ssl_context.set_params(cert_store: OpenSSL::X509::Store.new.tap { it.add_file(config.mqtt_ca_file) })
            client.ssl_context.alpn_protocols = ['mqtt']
          end
        end

        # @param error [Exception]
        # @return [Exception] an Error without the token for what the mqtt gem and the network raise; any other as it is
        def translated(error)
          return error unless [Timeout::Error, MQTT::Exception, *NETWORK_ERRORS].any? { error.is_a?(it) }

          host = Secure.config.mqtt_host
          return AuthenticationError.new("#{host}: #{error.message}") if REFUSED.match?(error.message)
          return TLSError.new("#{host}: #{error.message}") if error.message.include?('certificate verify failed')

          ConnectionError.new("#{host}: #{error.message}")
        end

        # @param packet [MQTT::Packet::Publish]
        # @return [Message]
        def message(packet)
          Message.new(topic: packet.topic.dup.force_encoding(Encoding::UTF_8).delete_prefix(@prefix),
                      payload: packet.payload.dup.force_encoding(Encoding::UTF_8))
        end
      end
    end
  end
end
