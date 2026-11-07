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

        # What the mqtt gem raises when the broker ends the connection between two packets.
        ENDED = 'Failed to read byte from socket'
        private_constant :ENDED

        # The mqtt gem's words for CONNACK 4 and 5.
        REFUSED = /bad user name or password|not authori[sz]ed/
        private_constant :REFUSED

        # Carries what the caller's block raised out of the gem, which would take an IOError of the caller's own code
        # for a network failure.
        class BlockFailure < StandardError
          # @return [Exception] what the block raised
          attr_reader :error

          # @param error [Exception]
          # @api private
          def initialize(error)
            @error = error
            super(error.message)
          end
        end
        private_constant :BlockFailure

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
          # Only receive and arrival let in what the gem's reader thread raises.
          masked(:never) { follow(&) }
        end

        private

        # @yieldparam message [Message]
        # @return [void]
        def follow(&)
          client = connect
          client.subscribe(@topics.to_h { ["#{@prefix}#{it}", 1] })
          receive(client, &)
        rescue BlockFailure => e
          raise e.error, cause: e.error.cause
        rescue *ends => e
          raise translated(e)
        ensure
          client&.disconnect
          # What the reader raised after the caller stopped, by an error or a break, must not replace it.
          arrival { Thread.pass }
        end

        # Why the connection ended gets in only while this thread waits for a message, so that none the gem read is
        # lost; what is still queued then goes to the block, without the acknowledgement the socket can no longer carry.
        #
        # @param client [MQTT::Client]
        # @yieldparam message [Message]
        # @return [void]
        def receive(client, &)
          masked(:on_blocking) { client.get_packet { |packet| deliver(packet.topic, packet.payload, &) } }
        rescue *ends => e
          e = verdict(client, e)
          client.get_packet { |packet| break deliver(packet.topic, packet.payload, &) } until client.queue_empty?
          raise e unless e.message == ENDED
        end

        # An acknowledgement fails once the reader thread has closed the socket, or once the broker is gone before the
        # reader sees it (2 follows in 2000 on 2026-11-08): why the connection ended still comes from the reader.
        #
        # @param client [MQTT::Client]
        # @param error [Exception] what stopped the receiving
        # @return [Exception] why the connection ended
        def verdict(client, error)
          return error unless error.is_a?(MQTT::NotConnectedException) || client.connected?

          arrival { sleep } || error
        end

        # @return [Exception, nil] what the gem's reader thread raised into this thread while the block ran
        def arrival(&)
          masked(:immediate, &)
          nil
        rescue *ends => e
          e
        end

        # @return [Array<Class>] what the gem's reader thread raises into this thread, wherever it is, when the
        #   connection ends
        def ends = [MQTT::Exception, *NETWORK_ERRORS]

        # @param mode [Symbol] when what the gem's reader thread raises gets in
        # @return [Object] what the block returns
        def masked(mode, &) = Thread.handle_interrupt(ends.to_h { [it, mode] }, &)

        # The gem bounds the TCP connection and the CONNACK, not the TLS handshake between them.
        #
        # @return [MQTT::Client] connected
        def connect
          config = Secure.config
          client = mqtt_client(config, "#{AUTHORIZER}#{Secure.session.current.value}")
          limit = config.open_timeout.to_f + config.read_timeout
          Timeout.timeout(limit, ConnectionError, "#{config.mqtt_host}: connecting took too long") { client.connect }
          client
        rescue StandardError, MQTT::Exception
          client&.disconnect(false)
          raise
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

        # The gem's reader thread raises what ends the connection into this thread; it waits until the block returns.
        #
        # @param topic [String]
        # @param payload [String]
        # @yieldparam message [Message]
        # @return [void]
        # @raise [BlockFailure] wrapping what the block raised
        def deliver(topic, payload)
          masked(:never) { yield message(topic, payload) }
        rescue StandardError => e
          raise BlockFailure, e
        end

        # @param error [Exception]
        # @return [Error] without the token
        def translated(error)
          host = Secure.config.mqtt_host
          return AuthenticationError.new("#{host}: #{error.message}") if REFUSED.match?(error.message)
          return TLSError.new("#{host}: #{error.message}") if error.message.include?('certificate verify failed')

          ConnectionError.new("#{host}: #{error.message}")
        end

        # @param topic [String]
        # @param payload [String]
        # @return [Message]
        def message(topic, payload)
          Message.new(topic: topic.dup.force_encoding(Encoding::UTF_8).delete_prefix(@prefix),
                      payload: payload.dup.force_encoding(Encoding::UTF_8))
        end
      end
    end
  end
end
