# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A channel of an Ajax camera or recorder, from the player catalogue (+stream_video_player+): what {Streams}
      # addresses. +ptz+ is its PTZ capability as the app reads it; +sub_stream+ and +sound+ are the catalogue's
      # sub stream flag and audio setting; +raw+ is the +PlayerChannel+.
      VideoChannel = Data.define(:space_id, :video_edge_id, :channel_id, :ptz, :sub_stream, :sound, :raw) do
        # @param space_id [String]
        # @param video_edge [Data] a +PlayerVideoEdge+
        # @param channel [Data] one of its +PlayerChannel+ values
        # @return [VideoChannel]
        def self.from(space_id, video_edge, channel)
          capabilities = channel.video_capabilities
          new(space_id:, video_edge_id: video_edge.id, channel_id: channel.id, ptz: ptz?(capabilities&.ptz),
              sub_stream: capabilities&.has_sub_stream == true, sound: channel.audio_settings&.enabled == true,
              raw: channel)
        end

        # The app's +qzh0+: a PTZ flag other than unspecified, or presets.
        #
        # @api private
        def self.ptz?(ptz) = !ptz.nil? && (ptz.flags.any? { it != :unspecified } || ptz.max_presets.positive?)
        private_class_method :ptz?
      end

      # The streams the app 3.59 asks a camera for over WebRTC, built as its +jbb1+ builds them. A {View} is what the
      # app gives one player: its channel, its +number+ and its quality. +tag+ (the +dcp_tag+) names each stream, as
      # the data channel addresses it; the numbers and the tags are each unique within a session.
      module Streams
        WEBRTC = Messages::Api::Mobile::V2::Common::Video::Webrtc
        VIDEO = Messages::Api::Mobile::V2::Common::Video
        # The metadata frames a live stream can carry, in the order the app asks for them.
        METADATA = %w[Figures A PirMotion RadarMotion].freeze
        private_constant :WEBRTC, :VIDEO

        # One player of a session: +quality+ is +:main+, or +:sub+ for a channel with a sub stream.
        View = Data.define(:channel, :number, :quality)

        module_function

        # @param view [View]
        # @param tag [Integer]
        # @param metadata [Array<String>] the metadata frames to add, among {METADATA}
        # @param ptz [Boolean] whether the view drives PTZ, which takes the capability and the +PTZ+ permission
        # @return [Data] a +Stream+ of live video
        # @raise [ArgumentError] for metadata outside {METADATA}
        def live(view, tag:, metadata: [], ptz: false)
          unknown = metadata - METADATA
          raise ArgumentError, "unknown metadata #{unknown.join(', ')}" unless unknown.empty?

          frames = [frame(:video), *(METADATA & metadata).map { frame(:metadata, it) }]
          live = WEBRTC::Stream::Live.new(use_ptz: ptz)
          stream(view, "l#{view.quality == :sub ? 's' : 'm'}", tag, frames, live:)
        end

        # @param view [View]
        # @param tag [Integer]
        # @param sound [Boolean] whether the stream carries the sound, which takes the +SOUND+ permission
        # @param talk_back [Boolean] whether the browser sends its voice, on a track whose stream id is +voice+
        # @return [Data] a +Stream+ of live sound
        def audio(view, tag:, sound: true, talk_back: false)
          live = WEBRTC::Stream::Live.new(input_rtc_stream_id: talk_back ? 'voice' : '')
          stream(view, 'l', tag, sound ? [frame(:audio)] : [], live:)
        end

        # @param view [View]
        # @param tag [Integer]
        # @param during [Range<Time>] the time range, to the second
        # @param sound [Boolean] whether the stream carries the sound
        # @param figures [Boolean] whether it carries the +Figures+ overlays
        # @return [Data] a +Stream+ of the camera's archive, whose position comes every second
        def archive(view, tag:, during:, sound: false, figures: false)
          frames = [frame(:video)]
          frames << frame(:audio) if sound
          frames << frame(:metadata, 'Figures') if figures
          archive = WEBRTC::Stream::Archive.new(ts_range: range(during), pos_update_interval: 1.0)
          stream(view, 'a', tag, frames, archive:)
        end

        # @param view [View]
        # @param tag [Integer]
        # @param during [Range<Time>] the time range, to the second
        # @return [Data] a +Stream+ of the archive's activity (+A+ frames), without video
        def activity(view, tag:, during:)
          archive = WEBRTC::Stream::Archive.new(ts_range: range(during))
          stream(view, 'activity', tag, [frame(:metadata, 'A')], archive:)
        end

        # @param view [View]
        # @param tag [Integer]
        # @return [Data] a +Stream+ of live thumbnails (+Thumbnail+ frames), which come from the sub stream
        def preview(view, tag:)
          live = WEBRTC::Stream::Live.new
          stream(view.with(quality: :sub), 'live-preview', tag, [frame(:metadata, 'Thumbnail')], live:)
        end

        def stream(view, kind, tag, filter, **source)
          WEBRTC::Stream.new(id: "#{view.number}-#{kind}", channel_guid: view.channel.channel_id, dcp_tag: tag,
                             type: view.quality, filter:, **source)
        end

        def frame(type, name = '') = VIDEO::FrameTypeId.new(frame_type: type, metadata_type: name)

        def range(during)
          VIDEO::TimestampRange.new(min_value: Time.at(during.begin.to_i), max_value: Time.at(during.end.to_i))
        end

        private_class_method :stream, :frame, :range
      end

      # The signaling of a WebRTC session with a camera, relayed between the cloud and a browser that plays it as
      # the app does: the far end offers, the browser answers, both trickle their ICE candidates. {#each} gives each
      # signal from the cloud as the Hash +RTCPeerConnection+ takes: the ICE servers as a configuration, a
      # description, a candidate. The session lasts until {#close}, which ends it as the app does.
      class LiveVideo
        REQUEST = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::StreamWebrtc::StreamWebrtcRequest
        WEBRTC = Messages::Api::Mobile::V2::Common::Video::Webrtc
        private_constant :REQUEST, :WEBRTC

        # @param exchange [Exchange] the +StreamWebrtc+ call, its init written
        # @param streams [Array<Data>] the streams of that init
        def initialize(exchange, streams)
          @exchange = exchange
          @streams = streams
          @ready = false
          @lock = Mutex.new
        end

        # Relays the cloud's signals until the session ends. When the cloud's init arrives, it sends the streams
        # again as {#ask_streams}, as the app does once its signaling is ready. The app ignores the answer to
        # {#ask_streams}, and so does this.
        #
        # @yieldparam signal [Hash{Symbol=>Object}] +{ iceServers: }+, +{ type:, sdp: }+ or
        #   +{ candidate:, sdpMid:, sdpMLineIndex: }+
        # @return [nil, Enumerator] an Enumerator of the signals when no block is given
        # @raise [ReadError] when the cloud refuses the session (+:permission_denied+, +:video_edge_is_offline+…)
        # @raise [IOError] when the session is closed or has run
        def each
          return enum_for(:each) unless block_given?

          @exchange.each do |message|
            ready if message.signaling_message == :init
            signal(message)&.then { yield it }
          end
        end

        # @param sdp [String] the browser's answer to the far end's offer
        # @return [self]
        # @raise [IOError] once the session has ended
        def answer(sdp) = write(answer: REQUEST::Answer.new(session_description: description('answer', sdp)))

        # @param sdp [String] an offer of the browser, as when it adds its talk-back track
        # @return [self]
        # @raise [IOError] once the session has ended
        def offer(sdp) = write(offer: REQUEST::Offer.new(session_description: description('offer', sdp)))

        # @param candidate [String] a candidate the browser gathered (+RTCIceCandidate#candidate+)
        # @param sdp_mid [String, nil]
        # @param sdp_mline_index [Integer, nil]
        # @return [self]
        # @raise [IOError] once the session has ended
        def candidate(candidate, sdp_mid:, sdp_mline_index:)
          found = WEBRTC::IceCandidate.new(sdp: candidate, sdp_mid: sdp_mid.to_s, sdp_mline_index: sdp_mline_index.to_i)
          write(new_ice_candidate: REQUEST::NewIceCandidate.new(candidate: found))
        end

        # Sends every stream the session should carry now, as the app does on each change of its list; before the
        # cloud's init, the list waits for it.
        #
        # @param streams [Array<Data>] from {Streams}
        # @return [self]
        # @raise [IOError] once the session has ended
        def ask_streams(streams)
          @lock.synchronize do
            @streams = streams
            write(ask_streams: REQUEST::AskStreams.new(streams:)) if @ready
          end
          self
        end

        # Tells the cloud the connection is up, as the app does once its peer connection is connected.
        #
        # @param latency [Float] seconds from the start of the session
        # @param candidate_type [Symbol] the selected candidate's type: +:host+, +:reflexive+ (+srflx+), +:relay+, or
        #   +:unspecified+ for any other, as the app sends a peer reflexive one
        # @param network [Symbol] +:ethernet+, +:wifi+, +:cellular+, or +:unspecified+ when it is not known
        # @return [self]
        # @raise [IOError] once the session has ended
        def established(latency:, candidate_type:, network:)
          write(peer_connection_established: REQUEST::PeerConnectionEstablished.new(
            latency:, ice_candidate_type: candidate_type, network_technology_type: network
          ))
        end

        # @return [nil]
        def close = @exchange.close

        private

        def ready
          @lock.synchronize do
            @ready = true
            write(ask_streams: REQUEST::AskStreams.new(streams: @streams))
          end
        end

        def write(**message)
          @exchange.write(REQUEST.new(**message))
          self
        end

        def description(type, sdp) = WEBRTC::SessionDescription.new(type:, sdp:)

        # The app types a description by the message that carries it, never by its +type+ field.
        def signal(message)
          case message.signaling_message
          when :init then { iceServers: message.init.ice_servers.map { ice_server(it) } }
          when :offer then description_of('offer', message.offer.session_description)
          when :answer then description_of('answer', message.answer.session_description)
          when :new_ice_candidate then candidate_of(message.new_ice_candidate.candidate)
          end
        end

        def ice_server(server) = { urls: server.urls, username: server.username, credential: server.credential }

        def description_of(type, found) = found && { type:, sdp: found.sdp }

        def candidate_of(found)
          found && { candidate: found.sdp, sdpMid: found.sdp_mid, sdpMLineIndex: found.sdp_mline_index }
        end
      end
    end
  end
end
