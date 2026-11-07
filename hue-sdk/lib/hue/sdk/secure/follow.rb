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
        include Enumerable

        # The topics the app follows and reads, under +dt:home/<home>/+.
        TOPICS = %w[arm/state arm/config arm/schedules device/+/config timeline/update].freeze

        NETWORK_ERRORS = [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError].freeze
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
        # @raise [AuthenticationError] if the broker refuses the token
        # @raise [TLSError] if the broker's certificate does not chain to the pinned root, or names another host
        # @raise [ConnectionError] if the broker cannot be reached, drops the connection, or leaves a ping unanswered
        # @api public
        def each
          link = connect
          begin
            transport { link.write(0x82, [1].pack('n') + @topics.sum(''.b) { Mqtt.string(@prefix + it) + "\x01".b }) }
            while (message = transport { following(link) })
              yield message
            end
          ensure
            link.close
          end
        end

        private

        # @return [Mqtt::Link] connected and acknowledged
        def connect
          username = "#{AUTHORIZER}#{Secure.session.current.value}"
          link = transport { Mqtt::Link.open(Secure.config, @keep_alive) }
          transport do
            link.write(0x10, hello(username))
            acknowledged(link.receive(within: Secure.config.read_timeout))
          end
          link
        rescue StandardError
          link&.close
          raise
        end

        # @param username [String]
        # @return [String] the body of CONNECT: MQTT 3.1.1, a clean session, the keep-alive, the gem's own client id
        def hello(username)
          Mqtt.string('MQTT') + [4, 0x82, @keep_alive].pack('CCn') + Mqtt.string("hue-sdk:#{SecureRandom.uuid}") +
            Mqtt.string(username)
        end

        # @yieldreturn [Object]
        # @return [Object] what the block returns
        # @raise [TLSError, ConnectionError] for a network error, without its token
        def transport
          yield
        rescue *NETWORK_ERRORS => e
          host = Secure.config.mqtt_host
          raise TLSError, "#{host}: #{e.message}" if e.message.include?('certificate verify failed')

          raise ConnectionError, "#{host}: #{e.message}"
        end

        # @param packet [Array(Integer, String), nil]
        # @return [void]
        # @raise [AuthenticationError] on CONNACK 4 or 5
        # @raise [ConnectionError] on any other refusal, or a dropped connection
        def acknowledged(packet)
          type, body = packet
          code = body&.getbyte(1)
          raise AuthenticationError, "the Hue Secure broker refused the token (#{code})" if [4, 5].include?(code)
          raise ConnectionError, "the Hue Secure broker refused the connection (#{type}, #{code})" unless code&.zero?
        end

        # @param link [Mqtt::Link]
        # @return [Message, nil] the next message; nil when the broker ends the connection
        def following(link)
          loop do
            type, body = link.receive
            return unless type && body
            return message(link, type, body) if type >> 4 == 3
          end
        end

        # Acknowledges a message at QoS 1, which the app subscribes at.
        #
        # @param link [Mqtt::Link]
        # @param type [Integer] the first byte of a PUBLISH
        # @param body [String]
        # @return [Message]
        def message(link, type, body)
          length = body.unpack1('n') #: Integer
          start = 2 + length
          if (type >> 1).anybits?(3)
            link.write(0x40, body.byteslice(start, 2).to_s)
            start += 2
          end
          topic = body.byteslice(2, length).to_s.force_encoding(Encoding::UTF_8).delete_prefix(@prefix)
          Message.new(topic:, payload: body.byteslice(start..).to_s.force_encoding(Encoding::UTF_8))
        end
      end
    end
  end
end
