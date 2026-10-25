# frozen_string_literal: true

require 'openssl'

module Miele
  module Sdk
    # MieleH256: the HMAC-SHA256 signature and AES-256-CBC encryption that every
    # message to or from a Miele appliance carries, keyed by the household
    # GroupKey (64 bytes: the whole key signs, its first half encrypts).
    module Crypto
      BLOCK = 16
      private_constant :BLOCK

      JSON_MINIMUM = 64
      private_constant :JSON_MINIMUM

      module_function

      # Pads a body with spaces the way the appliances do: a JSON object grows
      # to at least 64 bytes with spaces before its closing brace, then any body
      # to a multiple of 16 bytes.
      #
      # @param body [String] plaintext body
      # @return [String] padded body, signed and encrypted as is
      # @api public
      def pad(body)
        return body if body.empty?

        json = body.start_with?('{') && body.end_with?('}')
        size = [json ? JSON_MINIMUM : 0, body.bytesize].max
        spaces = ' ' * (size + (-size % BLOCK) - body.bytesize)
        json ? "#{body.delete_suffix('}')}#{spaces}}" : body + spaces
      end

      # Signs a message: each line followed by a newline, then the body. A
      # request signs its method, +host+ and path, +Content-Type+, +Accept+ and
      # +Date+; a response its status, +Content-Type+ and +Date+.
      #
      # @param key [String] GroupKey, 64 bytes
      # @param lines [Array<#to_s>] header lines of the message
      # @param body [String] padded plaintext body
      # @return [String] raw HMAC-SHA256
      # @api public
      def signature(key:, lines:, body:) = OpenSSL::HMAC.digest('SHA256', key, lines.map { "#{it}\n" }.join.b + body.b)

      # @param key [String] GroupKey, 64 bytes
      # @param signature [String] signature of the message, whose first 16 bytes are the IV
      # @param plaintext [String] padded plaintext
      # @return [String] ciphertext
      # @api public
      def encrypt(key:, signature:, plaintext:) = run(cipher(:encrypt, key, signature), plaintext)

      # @param key [String] GroupKey, 64 bytes
      # @param signature [String] signature of the message, whose first 16 bytes are the IV
      # @param ciphertext [String] encrypted body
      # @return [String] padded plaintext
      # @api public
      def decrypt(key:, signature:, ciphertext:) = run(cipher(:decrypt, key, signature), ciphertext)

      # @param group_id [String] GroupID, 8 bytes
      # @param signature [String] raw signature
      # @return [String] value of the +Authorization+ header
      # @api public
      def authorization(group_id:, signature:) = "MieleH256 #{hex(group_id)}:#{hex(signature)}"

      # @param bytes [String]
      # @return [String] upper-case hexadecimal digits
      # @api private
      def hex(bytes)
        digits = bytes.unpack1('H*') #: String
        digits.upcase
      end

      # @param mode [Symbol] +:encrypt+ or +:decrypt+
      # @param key [String]
      # @param signature [String]
      # @return [OpenSSL::Cipher]
      # @api private
      def cipher(mode, key, signature)
        OpenSSL::Cipher.new('aes-256-cbc').tap do |cipher|
          mode == :encrypt ? cipher.encrypt : cipher.decrypt
          cipher.padding = 0
          cipher.key = key.byteslice(0, 32).to_s
          cipher.iv = signature.byteslice(0, BLOCK).to_s
        end
      end

      # @param cipher [OpenSSL::Cipher]
      # @param data [String]
      # @return [String]
      # @api private
      def run(cipher, data) = cipher.update(data) + cipher.final
    end
  end
end
