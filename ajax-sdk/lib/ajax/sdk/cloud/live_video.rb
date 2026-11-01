# frozen_string_literal: true

module Ajax
  module Sdk
    module Cloud
      # A channel of an Ajax camera or recorder, from the player catalogue (+stream_video_player+): what {Streams}
      # addresses. +ptz+, +sub_stream+ and +sound+ are its PTZ capability, its sub stream and its audio setting, as
      # the app reads them to build its streams; +raw+ is the +PlayerChannel+.
      VideoChannel = Data.define(:space_id, :video_edge_id, :channel_id, :ptz, :sub_stream, :sound, :raw) do
        # @param space_id [String]
        # @param video_edge [Data] a +PlayerVideoEdge+
        # @param channel [Data] one of its +PlayerChannel+ values
        # @return [VideoChannel]
        def self.from(space_id, video_edge, channel)
          capabilities = channel.video_capabilities
          new(space_id:, video_edge_id: video_edge.id, channel_id: channel.id, ptz: !capabilities&.ptz.nil?,
              sub_stream: capabilities&.has_sub_stream == true, sound: channel.audio_settings&.enabled == true,
              raw: channel)
        end
      end

      # The streams the app 3.59 asks a camera for over WebRTC, built as its +jbb1+ builds them. A {View} is what the
      # app gives one player: its channel, its +number+ and its quality. +tag+ (the +dcp_tag+) names each stream, as
      # the data channel addresses it; the numbers and the tags are each unique within a session.
      module Streams
        WEBRTC = Messages::Api::Mobile::V2::Common::Video::Webrtc
        VIDEO = Messages::Api::Mobile::V2::Common::Video
        private_constant :WEBRTC, :VIDEO

        # One player of a session: +quality+ is +:main+, or +:sub+ for a channel with a sub stream.
        View = Data.define(:channel, :number, :quality)

        module_function

        # @param view [View]
        # @param tag [Integer]
        # @param metadata [Array<String>] the metadata frames to add: +Figures+, +A+, +PirMotion+, +RadarMotion+
        # @param ptz [Boolean] whether the view drives PTZ, which takes the capability and the +PTZ+ permission
        # @return [Data] a +Stream+ of live video
        def live(view, tag:, metadata: [], ptz: false)
          frames = [frame(:video), *metadata.map { frame(:metadata, it) }]
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
      # the app does: the camera offers, the browser answers, both trickle their ICE candidates. {#each} gives each
      # signal from the cloud as the Hash +RTCPeerConnection+ takes: the ICE servers as a configuration, a
      # description, a candidate. The session lasts until {#close}, which ends it as the app does.
      class LiveVideo
        REQUEST = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service::StreamWebrtc::StreamWebrtcRequest
        WEBRTC = Messages::Api::Mobile::V2::Common::Video::Webrtc
        private_constant :REQUEST, :WEBRTC

        # @param exchange [Exchange] the +StreamWebrtc+ call, its init written
        def initialize(exchange)
          @exchange = exchange
        end

        # Relays the cloud's signals until the session ends. The app ignores the answer to {#ask_streams}, and so
        # does this.
        #
        # @yieldparam signal [Hash{Symbol=>Object}] +{ iceServers: }+, +{ type:, sdp: }+ or
        #   +{ candidate:, sdpMid:, sdpMLineIndex: }+
        # @return [nil, Enumerator] an Enumerator of the signals when no block is given
        # @raise [ReadError] when the cloud refuses the session (+:permission_denied+, +:video_edge_is_offline+…)
        def each
          return enum_for(:each) unless block_given?

          @exchange.each { |message| signal(message)&.then { yield it } }
        end

        # @param sdp [String] the browser's answer to the camera's offer
        # @return [self]
        def answer(sdp) = write(answer: REQUEST::Answer.new(session_description: description('answer', sdp)))

        # @param sdp [String] an offer of the browser, as when it adds its talk-back track
        # @return [self]
        def offer(sdp) = write(offer: REQUEST::Offer.new(session_description: description('offer', sdp)))

        # @param candidate [String] a candidate the browser gathered (+RTCIceCandidate#candidate+)
        # @param sdp_mid [String]
        # @param sdp_mline_index [Integer]
        # @return [self]
        def candidate(candidate, sdp_mid:, sdp_mline_index:)
          found = WEBRTC::IceCandidate.new(sdp: candidate, sdp_mid:, sdp_mline_index:)
          write(new_ice_candidate: REQUEST::NewIceCandidate.new(candidate: found))
        end

        # @param streams [Array<Data>] every stream the session should carry now, from {Streams}: the app sends the
        #   whole list on each change
        # @return [self]
        def ask_streams(streams) = write(ask_streams: REQUEST::AskStreams.new(streams:))

        # Tells the cloud the connection is up, as the app does once its peer connection is connected.
        #
        # @param latency [Float] seconds from the start of the session
        # @param candidate_type [Symbol] the selected candidate's type: +:host+, +:reflexive+ or +:relay+
        # @param network [Symbol] +:ethernet+, +:wifi+ or +:cellular+
        # @return [self]
        def established(latency:, candidate_type:, network:)
          write(peer_connection_established: REQUEST::PeerConnectionEstablished.new(
            latency:, ice_candidate_type: candidate_type, network_technology_type: network
          ))
        end

        # @return [nil]
        def close = @exchange.close

        private

        def write(**message)
          @exchange.write(REQUEST.new(**message))
          self
        end

        def description(type, sdp) = WEBRTC::SessionDescription.new(type:, sdp:)

        def signal(message)
          case message.signaling_message
          when :init then { iceServers: message.init.ice_servers.map { ice_server(it) } }
          when :offer then description_of(message.offer.session_description)
          when :answer then description_of(message.answer.session_description)
          when :new_ice_candidate then candidate_of(message.new_ice_candidate.candidate)
          end
        end

        def ice_server(server) = { urls: server.urls, username: server.username, credential: server.credential }

        def description_of(found) = found && { type: found.type, sdp: found.sdp }

        def candidate_of(found)
          found && { candidate: found.sdp, sdpMid: found.sdp_mid, sdpMLineIndex: found.sdp_mline_index }
        end
      end
    end
  end
end
