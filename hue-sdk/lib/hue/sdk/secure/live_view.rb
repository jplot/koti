# frozen_string_literal: true

require 'base64'
require 'json'
require 'securerandom'
require 'uri'

module Hue
  module Sdk
    module Secure
      # The signaling of a camera's live view, as the app's: the gem relays the browser's offer and ICE candidates to
      # the camera over Kinesis Video's WebSocket, signs the offer with the home's keys, and yields what the camera
      # sends back, its SDP verified. The browser holds the peer connection and the media. Never tested on a device.
      class LiveView
        include Enumerable

        # The camera's offer, which {#answer} answers.
        Offer = Data.define(:sdp)

        # The camera's answer to {#offer}, signed by the camera.
        Answer = Data.define(:sdp)

        # An ICE candidate of the camera.
        Candidate = Data.define(:candidate, :sdp_mid, :sdp_mline_index)

        # Another message of the channel, as Kinesis Video sent it: the app reads none of them.
        Message = Data.define(:type, :message)

        # The data channel the browser opens before its offer, as the app does: it sends +ping+ every +interval+
        # seconds, expects +pong+, and sends +go_away+ when it stops.
        DATA_CHANNEL = { label: 'messages', ping: 'PING', pong: 'PONG', go_away: 'GO_AWAY', interval: 1 }.freeze

        PURPOSE = 'a Hue Secure live view'
        UNKNOWN = 'Could not find signaling channel / turn server config for the camera on the remote server'
        private_constant :PURPOSE, :UNKNOWN

        # @return [Array<Hash{Symbol=>Object}>] the browser's RTCIceServer list: each STUN server, then the camera's
        #   TURN servers
        attr_reader :ice_servers

        # @return [String, nil] when the first of the credentials expires, as the cloud gives it
        attr_reader :earliest_expiry

        # @param home_id [String]
        # @param camera_id [String]
        # @param keys [E2ee::Keys]
        # @param signing_key_id [String]
        # @return [LiveView] connected
        # @api private
        def self.open(home_id, camera_id, keys:, signing_key_id:)
          Media.load('websocket/driver', PURPOSE, gem: 'websocket-driver')
          path = "security/vss/v1/home/#{home_id}/credentials/live-stream"
          body = { device_id_list: Cameras.new(home_id).list.map(&:id) }
          answer = Secure.client.post(path, query: { turn_servers: true }, body:).body
          new(Schema::SignalingConfiguration.from(answer), camera_id, keys:, signing_key_id:)
        end

        # The signaling URL, presigned for 299 s as the app presigns it.
        #
        # @param endpoint [String] the channel's +wss+ endpoint
        # @param channel_arn [String]
        # @param client_id [String]
        # @param credentials [Schema::SignalingServerCredentials]
        # @param time [Time]
        # @return [String]
        # @api private
        def self.presign(endpoint, channel_arn:, client_id:, credentials:, time: Time.now)
          Media.load('aws-sigv4', PURPOSE)
          signer = Aws::Sigv4::Signer.new(service: 'kinesisvideo', region: Secure.config.kinesis_region,
                                          access_key_id: credentials.AccessKeyId,
                                          secret_access_key: credentials.SecretAccessKey,
                                          session_token: credentials.SessionToken)
          query = URI.encode_www_form('X-Amz-ChannelARN' => channel_arn, 'X-Amz-ClientId' => client_id)
          signer.presign_url(http_method: 'GET', url: "#{endpoint}/?#{query}", expires_in: 299, time:).to_s
        end

        # @param configuration [Schema::SignalingConfiguration]
        # @param camera_id [String]
        # @param keys [E2ee::Keys]
        # @param signing_key_id [String]
        # @raise [ResponseError] if the configuration has no channel or TURN server for the camera
        # @api private
        def initialize(configuration, camera_id, keys:, signing_key_id:)
          channel, turn = entries(configuration, camera_id)
          @ice_servers = ice(configuration, turn)
          @earliest_expiry = configuration.earliest_expiry
          @client_id = "hue-sdk_#{SecureRandom.uuid}"
          @app_key = keys.app
          @camera_key = keys.camera(camera_id)
          @signing_key_id = signing_key_id
          @channel = connected(turn.wss_signal_channel_endpoint, channel.arn, configuration.credentials)
        end

        # @return [String]
        def inspect = "#<#{self.class.name} #{@client_id}>"

        # Sends the browser's offer, signed with the app key.
        #
        # @param sdp [String]
        # @return [void]
        # @raise [ConnectionError] if the channel is closed
        # @api public
        def offer(sdp) = deliver('SDP_OFFER', signed(sdp, 'offer'), senderClientId: @client_id)

        # Answers the camera's {Offer}, to +ConsumerViewer+ as the app does.
        #
        # @param sdp [String] the browser's answer
        # @return [void]
        # @raise [ConnectionError] if the channel is closed
        # @api public
        def answer(sdp) = deliver('SDP_ANSWER', signed(sdp, 'answer'), recipientClientId: 'ConsumerViewer')

        # Sends one of the browser's ICE candidates; one without a candidate, as at the end of gathering, is dropped
        # as the app drops it.
        #
        # @param candidate [String, nil]
        # @param sdp_mid [String, nil]
        # @param sdp_mline_index [Integer, nil]
        # @return [void]
        # @raise [ConnectionError] if the channel is closed
        # @api public
        def candidate(candidate, sdp_mid:, sdp_mline_index:)
          return if candidate.to_s.empty?

          deliver('ICE_CANDIDATE', { candidate:, sdpMid: sdp_mid, sdpMLineIndex: sdp_mline_index },
                  senderClientId: @client_id)
        end

        # Reads the channel on the caller's thread until {#close}, which another thread may call.
        #
        # @yieldparam signal [Answer, Offer, Candidate, Message]
        # @return [void]
        # @raise [E2eeError] if the camera did not sign its SDP
        # @raise [ConnectionError] if Kinesis Video closes the channel or drops the connection
        # @api public
        def each
          return enum_for(:each) unless block_given?

          @channel.each_text { yield signal(it) }
        end

        # @return [void]
        # @api public
        def close = @channel.close

        private

        def entries(configuration, camera_id)
          channel = configuration.signaling_channels.find { it.id == camera_id }
          turn = configuration.turn_servers&.find { it.device_id == camera_id }
          raise ResponseError.new(200, [UNKNOWN], source: 'Hue cloud') unless channel && turn

          [channel, turn]
        end

        def connected(endpoint, channel_arn, credentials)
          Channel.new(LiveView.presign(endpoint, channel_arn:, client_id: @client_id, credentials:))
        end

        def ice(configuration, turn)
          (configuration.stun_servers || []).map { { urls: [it] } } +
            turn.ice_servers.map { { urls: it.urls, username: it.username, credential: it.password } }
        end

        def signed(sdp, type)
          { type:, sdp:, hueSignature: E2ee.sign(@app_key, sdp), hueSender: @client_id,
            hueHomeSigningPublicKeyUuid: @signing_key_id }
        end

        def deliver(action, payload, **to)
          text = JSON.generate({ action:, messagePayload: Base64.strict_encode64(JSON.generate(payload)), **to })
          @channel.write(text)
        end

        def signal(text)
          message = JSON.parse(text)
          case message['messageType']
          when 'SDP_ANSWER' then Answer.new(sdp: verified(message))
          when 'SDP_OFFER' then Offer.new(sdp: verified(message))
          when 'ICE_CANDIDATE' then candidate_of(payload(message))
          else Message.new(type: message['messageType'], message:)
          end
        end

        def candidate_of(payload)
          Candidate.new(candidate: payload['candidate'], sdp_mid: payload['sdpMid'],
                        sdp_mline_index: payload['sdpMLineIndex'])
        end

        def verified(message)
          payload = payload(message)
          sdp = payload['sdp'].to_s
          E2ee.verify(@camera_key, sdp, payload['hueSignature'])
          sdp
        end

        def payload(message) = JSON.parse(Base64.decode64(message['messagePayload'].to_s))
      end
    end
  end
end

require_relative 'live_view/channel'
