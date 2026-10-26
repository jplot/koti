# frozen_string_literal: true

require 'openssl'

# DC-09 frames built the way a hub builds them; the cipher goes straight to OpenSSL so the specs do not
# lean on Sia::Cipher.
module SiaFrames
  KEY = '0123456789ABCDEF'

  def sia_frame(body) = "\n#{format('%04X', Ajax::Sdk::Sia.crc(body))}#{format('%04X', body.bytesize)}#{body}\r"

  def sia_stamp(time = Time.now) = time.utc.strftime('_%H:%M:%S,%m-%d-%Y')

  def sia_encrypt(text, key = KEY)
    cipher = sia_cipher(:encrypt, key)
    (cipher.update(text) + cipher.final).unpack1('H*').upcase
  end

  def sia_decrypt(hex, key = KEY) = sia_cipher(:decrypt, key).then { it.update([hex].pack('H*')) + it.final }

  def sia_cipher(direction, key)
    cipher = OpenSSL::Cipher.new("aes-#{key.bytesize * 8}-cbc").public_send(direction)
    cipher.key = key
    cipher.iv = "\0" * 16
    cipher.padding = 0
    cipher
  end

  def encrypted_sia_frame(type, data, key: KEY, time: Time.now, sequence: '0001')
    plain = "|#{data}]#{sia_stamp(time)}"
    plain = plain.rjust(plain.size + 16 - (plain.size % 16), 'p')
    sia_frame(%("*#{type}"#{sequence}R0L0#AAA[#{sia_encrypt(plain, key)}))
  end
end

RSpec.configure { |config| config.include SiaFrames }
