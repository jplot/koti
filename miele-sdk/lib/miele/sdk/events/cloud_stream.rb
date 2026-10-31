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
          @websocket.each do |message|
            event = event(message)
            yield event if event
          end
        end

        private

        # @param message [Cloud::Websocket::Message]
        # @return [Event, nil] nil for a resource the app does not read from the websocket
        def event(message)
          body = message.body.dup.force_encoding(Encoding::UTF_8)
          if message.path == '/V2/Devices'
            return Event.new(fab: nil, resource: '/Devices/', content: JSON.parse(body), source: :cloud)
          end

          match = PATH.match(message.path)
          content = match && content(match[:rest].to_s, body)
          Event.new(fab: match[:fab], resource: "/#{match[:rest]}/", content:, source: :cloud) if match && content
        end

        # @param rest [String] the path past the appliance
        # @param body [String]
        # @return [Hash{String=>Object}, Dop2::Leaf, nil]
        def content(rest, body)
          case rest
          when 'State', 'Ident' then JSON.parse(body)
          when %r{\ADOP2/\d+/\d+\z} then Dop2.decode(body.b)
          end
        end
      end
    end
  end
end
