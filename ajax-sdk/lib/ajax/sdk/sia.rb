# frozen_string_literal: true

require_relative 'sia/cipher'
require_relative 'sia/message'

module Ajax
  module Sdk
    # The local SIA DC-09 side: the hub sends its events straight to koti over TCP, without the cloud.
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
