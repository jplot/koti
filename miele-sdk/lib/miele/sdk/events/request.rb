# frozen_string_literal: true

require 'openssl'

module Miele
  module Sdk
    module Events
      # A request an appliance sends to the {Server}, as read from its connection.
      class Request
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
        # @api private
        def self.read(socket)
          verb, path = socket.gets("\r\n").to_s.split
          return unless verb && path

          headers = read_headers(socket)
          new(verb:, path:, headers:, body: socket.read(headers.fetch('content-length', '0').to_i).to_s)
        end

        # @param socket [TCPSocket]
        # @return [Hash{String=>String}] by lowercase name
        # @api private
        def self.read_headers(socket)
          headers = {} #: Hash[String, String]
          while (line = socket.gets("\r\n")) && line != "\r\n"
            name, value = line.chomp("\r\n").split(': ', 2)
            headers[name.to_s.downcase] = value.to_s
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

        private

        # @return [String, nil] the signature, nil unless the request claims the household's GroupID
        def claimed_signature
          group_id, signature = headers['authorization'].to_s.delete_prefix('MieleH256 ').split(':', 2)
          [signature].pack('H*') if signature && [group_id].pack('H*') == Connection.credentials.first
        end

        # @return [Array<String>] method, host and path, Content-Type, Accept and Date
        def signed_lines
          [verb, "#{headers['host']}#{path}", *headers.values_at('content-type', 'accept', 'date').map(&:to_s)]
        end
      end
    end
  end
end
