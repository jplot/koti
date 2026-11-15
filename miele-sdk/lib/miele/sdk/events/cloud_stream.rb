# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Events
      # The account's appliances followed through the Miele cloud websocket as the app follows them: the State of
      # each read again on every connection, then whatever the cloud pushes.
      class CloudStream
        # ResponseInterpreterRepository's route: a fabrication number, or a module's +mac-…+ id.
        PATH = %r{\A/V2/Devices/(?<fab>\d{7,12}|(?i:mac-[0-9a-f]+))/(?<rest>.+)\z}
        private_constant :PATH

        # @param channel [Cloud::Channel] the account
        def initialize(channel)
          follow = -> { channel.devices.map { "/Devices/#{it.fab}/State" } }
          @websocket = Cloud::Websocket.new(channel.session, follow:,
                                                             fetch: ->(path) { channel.request(:get, path).body })
        end

        # @yieldparam event [Event] with +source+ +:cloud+
        # @return [void]
        # @api public
        def each
          @websocket.each { |message| yield event(message) }
        end

        private

        # The app reads State, Ident, DOP2 leaves and the device list from the websocket; the others pass too.
        #
        # @param message [Cloud::Websocket::Message]
        # @return [Event] under the appliance's resource, or under its own path for a push outside any appliance
        def event(message)
          body = message.body.dup.force_encoding(Encoding::UTF_8)
          if message.path == '/V2/Devices'
            return Event.new(fab: nil, resource: '/Devices/', content: JSON.parse(body), source: :cloud)
          end

          match = PATH.match(message.path)
          return Event.new(fab: nil, resource: message.path, content: content('', body), source: :cloud) unless match

          rest = match[:rest].to_s
          Event.new(fab: match[:fab], resource: "/#{rest}/", content: content(rest, body), source: :cloud)
        end

        # @param rest [String] the path past the appliance
        # @param body [String]
        # @return [Hash{String=>Object}, Array, Dop2::Leaf, String] the leaf decoded, else the JSON parsed, else the
        #   body as pushed
        def content(rest, body)
          return Dop2.decode(body.b) if rest.match?(%r{\ADOP2/\d+/\d+\z})

          JSON.parse(body)
        rescue JSON::ParserError
          body
        end
      end
    end
  end
end
