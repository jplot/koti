# frozen_string_literal: true

require 'net/http'
require 'uri'

module Hue
  module Sdk
    module Secure
      # A clip of a camera, as the event service hands it out: an HLS playlist that carries its own authorization, and
      # whose media segments the camera encrypted. The gem reads it as the app's local proxy does. Never tested on a
      # device.
      class Clip
        # @return [URI::HTTP] the playlist the event service gave
        attr_reader :url

        # @return [Numeric] as the event service gave it; its unit is unknown, and the app does not read it
        attr_reader :expiration

        # @param url [URI::HTTP]
        # @param expiration [Numeric]
        # @param cek [String] the content key of the clip
        # @api private
        def initialize(url, expiration, cek)
          @url = url
          @expiration = expiration
          @cek = cek
          @lock = Mutex.new
        end

        # @return [String] the path and query of the playlist: what a player asks for first
        # @api public
        def entry = [url.path, url.query].compact.join('?')

        # A file of the clip: playlists and the initialization segment as they are, media segments decrypted.
        #
        # @param path [String] relative to the playlist, as a player asks for it
        # @return [Http::Response] the answer of the clip's host, its media segment in clear
        # @raise [ArgumentError] if the path leads out of the clip's host
        # @raise [E2eeError] if a media segment does not decrypt
        # @raise [ResponseError] if the clip's playlists or initialization segment are refused
        # @raise [ConnectionError] if the clip's host cannot be reached
        # @api public
        def get(path)
          target = URI.join(url, path) #: URI::HTTP
          raise ArgumentError, "#{path} is not a file of the clip" unless local?(target)

          answer = Http.fetch(target)
          Http::Response.new(status: answer.code.to_i, body: clear(answer), headers: answer.each_header.to_h)
        end

        # @param uri [URI::HTTP]
        # @return [Boolean] whether it is on the clip's host: a player sent elsewhere would leave the proxy
        # @api private
        def local?(uri) = origin(uri) == origin(url)

        private

        def origin(uri) = [uri.scheme, uri.host, uri.port]

        def clear(answer)
          body = answer.body.to_s
          return body unless answer.is_a?(Net::HTTPOK) && Mp4.media?(body)

          Mp4.segment(body, init:) { E2ee.decrypt(@cek, it) }
        end

        # GPAC reads a media segment only with the clip's initialization segment, which the media playlist names.
        def init = @lock.synchronize { @init ||= read(map) }

        def map
          playlist_url, playlist = media_playlist
          item = playlist.items.find { it.is_a?(M3u8::MapItem) }
          raise E2eeError, 'the clip names no initialization segment' unless item

          URI.join(playlist_url, item.uri) #: URI::HTTP
        end

        def media_playlist
          Media.load('m3u8', 'reading a Hue Secure clip')
          playlist = M3u8::Playlist.read(read(url))
          return [url, playlist] unless playlist.master?

          variant = URI.join(url, playlist.items.first.uri) #: URI::HTTP
          [variant, M3u8::Playlist.read(read(variant))]
        end

        def read(target)
          answer = Http.fetch(target)
          raise ResponseError.new(answer.code.to_i, [], source: target.host.to_s) unless answer.is_a?(Net::HTTPSuccess)

          answer.body.to_s
        end
      end
    end
  end
end
