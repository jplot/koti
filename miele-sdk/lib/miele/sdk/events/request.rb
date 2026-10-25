# frozen_string_literal: true

require 'openssl'

module Miele
  module Sdk
    module Events
      # A request an appliance sends to the {Server}, as read from its connection.
      class Request
        # A request beyond the limits below, answered 400.
        class Malformed < StandardError; end

        # Pushes are a few hundred bytes of JSON: anything far larger is not an appliance.
        LINE_LIMIT = 8192
        HEADER_LIMIT = 100
        BODY_LIMIT = 65_536
        private_constant :LINE_LIMIT, :HEADER_LIMIT, :BODY_LIMIT

        # @return [String] HTTP method
        attr_reader :verb

        # @return [String] path, query included
        attr_reader :path

        # @return [Hash{String=>String}] headers by lowercase name
        attr_reader :headers

        # @return [String] encrypted body, empty without one
        attr_reader :body

        # @param socket [TCPSocket]
        # @return [Request, nil] nil when the peer closed the connection without a request
        # @raise [Malformed] if a line, the headers or the body exceed their limits
        # @api private
        def self.read(socket)
          verb, path = read_line(socket)&.split
          return unless verb && path

          headers = read_headers(socket)
          length = Integer(headers.fetch('content-length', '0'), exception: false)
          raise Malformed, "Content-Length #{headers['content-length']}" unless length&.between?(0, BODY_LIMIT)

          new(verb:, path:, headers:, body: socket.read(length).to_s)
        end

        # @param socket [TCPSocket]
        # @return [String, nil] the line without its CRLF, nil at the end of the stream
        # @raise [Malformed]
        # @api private
        def self.read_line(socket)
          line = socket.gets("\r\n", LINE_LIMIT) or return
          raise Malformed, 'line too long' unless line.end_with?("\r\n")

          line.chomp("\r\n")
        end
        private_class_method :read_line

        # @param socket [TCPSocket]
        # @return [Hash{String=>String}] by lowercase name
        # @raise [Malformed]
        # @api private
        def self.read_headers(socket)
          headers = {} #: Hash[String, String]
          while (line = read_line(socket)) && !line.empty?
            raise Malformed, 'too many headers' if headers.size == HEADER_LIMIT

            # Appliances send +Content-Length:608+, without a space after the colon.
            name, value = line.split(':', 2)
            headers[name.to_s.downcase] = value.to_s.strip
          end
          headers
        end
        private_class_method :read_headers

        # @param verb [String]
        # @param path [String]
        # @param headers [Hash{String=>String}]
        # @param body [String]
        def initialize(verb:, path:, headers:, body:)
          @verb = verb
          @path = path
          @headers = headers
          @body = body
        end

        # @return [String, nil] the decrypted body, nil unless the household key signed the request
        # @api private
        def plaintext
          signature = claimed_signature or return
          key = Connection.credentials.last
          plaintext = body.empty? ? '' : Crypto.decrypt(key:, signature:, ciphertext: body)
          plaintext if OpenSSL.secure_compare(Crypto.signature(key:, lines: signed_lines, body: plaintext), signature)
        rescue OpenSSL::Cipher::CipherError
          nil
        end

        # @return [Boolean] whether the request claims the household's GroupID
        # @api private
        def household?
          group_id = headers['authorization'].to_s.delete_prefix('MieleH256 ').split(':', 2).first.to_s
          [group_id].pack('H*') == Connection.credentials.first
        end

        private

        # @return [String, nil] the signature, nil unless the request claims the household and carries one
        def claimed_signature
          signature = [headers['authorization'].to_s.split(':', 2).last.to_s].pack('H*')
          signature if household? && signature.bytesize == 32
        end

        # @return [Array<String>] method, host and path, Content-Type, Accept and Date
        def signed_lines
          [verb, "#{headers['host']}#{path}", *headers.values_at('content-type', 'accept', 'date').map(&:to_s)]
        end
      end
    end
  end
end
