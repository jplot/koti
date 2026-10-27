# frozen_string_literal: true

require 'openssl'

module Ajax
  module Sdk
    module Sia
      # AES-128-CBC the way Ajax hubs use it for DC-09: a zero IV, no cipher padding, and a key of 16
      # characters taken as its bytes, or of 32 hexadecimal digits.
      class Cipher
        IV = ("\0" * 16).b.freeze
        private_constant :IV

        # @param key [String] the encryption key set on the hub
        # @raise [ConfigurationError] when the key is neither 16 characters nor 32 hexadecimal digits
        def initialize(key)
          @key = if key.match?(/\A\h{32}\z/)
                   [key].pack('H*')
                 elsif key.bytesize == 16
                   key.b
                 else
                   raise ConfigurationError, 'the SIA key must be 16 characters or 32 hexadecimal digits'
                 end
        end

        # @return [String] a description that never prints the key
        def inspect = "#<#{self.class.name}>"

        # @param hex [String] the encrypted part of a frame, in hexadecimal, whole blocks only
        # @return [String] the plaintext with its padding, as binary
        def decrypt(hex) = run(:decrypt, [hex].pack('H*'))

        # Left-pads +text+ with zeros to whole blocks, then encrypts it.
        #
        # @param text [String]
        # @return [String] the ciphertext in uppercase hexadecimal
        def encrypt(text)
          padded = text.rjust(text.bytesize + 16 - (text.bytesize % 16), '0')
          run(:encrypt, padded).unpack1('H*').to_s.upcase
        end

        private

        def run(direction, data)
          cipher = OpenSSL::Cipher.new('aes-128-cbc').public_send(direction)
          cipher.key = @key
          cipher.iv = IV
          cipher.padding = 0
          cipher.update(data) + cipher.final
        end
      end
    end
  end
end
