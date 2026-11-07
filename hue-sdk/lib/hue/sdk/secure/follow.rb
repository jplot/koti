# frozen_string_literal: true

require 'json'
require 'openssl'
require 'securerandom'
require 'socket'

module Hue
  module Sdk
    module Secure
      # Follows a home over the MQTT broker of Hue Secure, as the app's +BaseHomeMqttClient+ does: TLS with ALPN
      # +mqtt+ to the one root the app pins, MQTT 3.1.1, the token in the username of AWS IoT's custom authorizer.
      # It reads once and never publishes. Never tested on a device.
      class Follow
        # The topics the app follows and reads, under +dt:home/<home>/+.
        TOPICS = %w[arm/state arm/config arm/schedules device/+/config timeline/update].freeze

        NETWORK_ERRORS = [SocketError, SystemCallError, IOError, EOFError].freeze
        private_constant :NETWORK_ERRORS

        AUTHORIZER = 'app?x-amz-customauthorizer-name=mqtt-app-authorizer&token='
        private_constant :AUTHORIZER

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
        # @api public
        def initialize(home_id, topics:)
          @prefix = "dt:home/#{home_id}/"
          @topics = topics
        end

        # Follows the home until the broker ends the connection; the caller decides whether to follow it again.
        #
        # @yieldparam message [Message]
        # @return [void]
        # @raise [AuthenticationError] if the broker refuses the token
        # @raise [TLSError] if the broker's certificate does not chain to the pinned root
        # @raise [ConnectionError] if the broker cannot be reached, or drops the connection before following
        # @api public
        def each
          socket = connect
          subscribe(socket)
          read(socket) { yield it }
        ensure
          socket&.close
        end

        private

        # @return [OpenSSL::SSL::SSLSocket]
        def connect
          config = Secure.config
          username = "#{AUTHORIZER}#{Secure.session.current.value}"
          socket = tls(config)
          socket.write(Mqtt.packet(0x10, Mqtt.string('MQTT') + [4, 0x82, 60].pack('CCn') +
                                         Mqtt.string("hue-sdk:#{SecureRandom.uuid}") + Mqtt.string(username)))
          acknowledged(socket)
          socket
        end

        # @param config [Configuration::Settings]
        # @return [OpenSSL::SSL::SSLSocket]
        # @raise [TLSError, ConnectionError]
        def tls(config)
          tcp = Socket.tcp(config.mqtt_host, config.mqtt_port, connect_timeout: config.open_timeout)
          socket = OpenSSL::SSL::SSLSocket.new(tcp, context(config))
          socket.hostname = config.mqtt_host
          socket.sync_close = true
          socket.connect
        rescue OpenSSL::SSL::SSLError, *NETWORK_ERRORS => e
          verify = e.message.include?('certificate verify failed')
          raise (verify ? TLSError : ConnectionError), "#{config.mqtt_host}: #{e.message}"
        end

        # @param config [Configuration::Settings]
        # @return [OpenSSL::SSL::SSLContext] trusting the pinned root alone, offering ALPN +mqtt+
        def context(config)
          OpenSSL::SSL::SSLContext.new.tap do |context|
            context.set_params(cert_store: OpenSSL::X509::Store.new.tap { it.add_file(config.mqtt_ca_file) })
            context.alpn_protocols = ['mqtt']
          end
        end

        # @param socket [OpenSSL::SSL::SSLSocket]
        # @return [void]
        # @raise [AuthenticationError] on CONNACK 4 or 5
        # @raise [ConnectionError] on any other refusal, or a dropped connection
        def acknowledged(socket)
          type, body = Mqtt.received(socket)
          code = body.getbyte(1)
          raise AuthenticationError, "the Hue Secure broker refused the token (#{code})" if [4, 5].include?(code)
          raise ConnectionError, "the Hue Secure broker refused the connection (#{type}, #{code})" unless code&.zero?
        rescue *NETWORK_ERRORS => e
          raise ConnectionError, "#{Secure.config.mqtt_host}: #{e.message}"
        end

        # @param socket [OpenSSL::SSL::SSLSocket]
        # @return [void]
        def subscribe(socket)
          filters = @topics.sum('') { Mqtt.string("#{@prefix}#{it}") + "\x00".b }
          socket.write(Mqtt.packet(0x82, [1].pack('n') + filters))
        end

        # @param socket [OpenSSL::SSL::SSLSocket]
        # @yieldparam message [Message]
        # @return [void]
        def read(socket)
          loop do
            ready = socket.wait_readable(60)
            next socket.write(Mqtt.packet(0xc0, '')) unless ready

            type, body = Mqtt.received(socket)
            yield message(type, body) if type >> 4 == 3
          end
        rescue IOError
          nil
        end

        # @param type [Integer] the first byte of a PUBLISH
        # @param body [String]
        # @return [Message]
        def message(type, body)
          length = body.unpack1('n') #: Integer
          start = 2 + length + (((type >> 1) & 3).clamp(0, 1) * 2)
          topic = body.byteslice(2, length).to_s.delete_prefix(@prefix)
          Message.new(topic:, payload: body.byteslice(start..).to_s)
        end
      end
    end
  end
end
