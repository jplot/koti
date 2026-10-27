# frozen_string_literal: true

require_relative 'sia/cipher'
require_relative 'sia/message'
require_relative 'sia/codes'
require_relative 'sia/event'
require_relative 'sia/receiver'

module Ajax
  module Sdk
    # The local SIA DC-09 side: the hub sends its events straight to a {Receiver} over TCP, without the
    # cloud. {Ajax::Sdk.sia_events} runs one with the configured settings.
    module Sia
      # @param text [String] a frame from its first +"+ up to, not including, its +\r+
      # @return [Integer] the CRC-16/ARC that DC-09 writes in front of each frame
      def self.crc(text)
        text.each_byte.reduce(0) do |crc, byte|
          crc ^= byte
          8.times { crc = crc.odd? ? (crc >> 1) ^ 0xA001 : crc >> 1 }
          crc
        end
      end
    end
  end
end
