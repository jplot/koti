# frozen_string_literal: true

require 'uri'

module Hue
  module Sdk
    module Secure
      # A Rack application that serves one clip to a player, its media segments decrypted, as the app's local proxy
      # does. The application mounts it behind its own authentication; the player first asks for +clip.entry+.
      class ClipProxy
        # @param clip [Clip]
        # @api public
        def initialize(clip)
          @clip = clip
        end

        # @param env [Hash{String=>Object}] a Rack environment
        # @return [Array(Integer, Hash{String=>String}, Array<String>)] 404 for a path off the clip's host, 502 with
        #   no body when the clip's host cannot be reached, redirects off it, or a segment does not decrypt
        # @api public
        def call(env)
          return [405, {}, []] unless env['REQUEST_METHOD'] == 'GET'

          query = env['QUERY_STRING'].to_s
          path = query.empty? ? env['PATH_INFO'].to_s : "#{env['PATH_INFO']}?#{query}"
          target = URI.join(@clip.url, path) #: URI::HTTP
          return [404, {}, []] unless @clip.local?(target)

          answer = @clip.get(path)
          [answer.status, headers(env, path, answer), [answer.body]]
        rescue E2eeError, ConnectionError, ResponseError
          [502, {}, []]
        end

        private

        def headers(env, path, answer)
          kept = { 'content-type' => answer.headers['content-type'], 'content-length' => answer.body.bytesize.to_s }
          location = answer.headers['location'] or return kept.compact

          target = URI.join(@clip.url, path, location) #: URI::HTTP
          kept.merge('location' => "#{env['SCRIPT_NAME']}#{moved(target, answer)}").compact
        end

        def moved(uri, answer)
          raise ResponseError.new(answer.status, ["redirected to #{uri.host}"], source: 'clip') unless @clip.local?(uri)

          [uri.path, uri.query].compact.join('?')
        end
      end
    end
  end
end
