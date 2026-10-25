# frozen_string_literal: true

require 'openssl'
require 'rbconfig'

module Hue
  module Sdk
    module Entertainment
      # Bindings to the DTLS client of libssl: Ruby's OpenSSL extension offers
      # neither DTLS nor pre-shared keys. They use the libssl Ruby's extension
      # links, or the library named by +HUE_SDK_LIBSSL+.
      module LibSSL
        extend FFI::Library

        # dlsym on the extension's handle searches only it and its dependencies; the
        # whole process answers with the first libssl loaded, LibreSSL 3.3.6 on macOS.
        ffi_lib ENV.fetch('HUE_SDK_LIBSSL') { $LOADED_FEATURES.find { it.end_with?("/openssl.#{RbConfig::CONFIG['DLEXT']}") } }

        callback :psk_client_callback, %i[pointer string pointer uint pointer uint], :uint

        attach_function :DTLS_client_method, [], :pointer
        attach_function :SSL_CTX_new, [:pointer], :pointer
        attach_function :SSL_CTX_set_cipher_list, %i[pointer string], :int
        attach_function :SSL_CTX_set_psk_client_callback, %i[pointer psk_client_callback], :void
        attach_function :SSL_CTX_free, [:pointer], :void
        attach_function :SSL_new, [:pointer], :pointer
        attach_function :SSL_set_fd, %i[pointer int], :int
        attach_function :SSL_connect, [:pointer], :int, blocking: true
        attach_function :SSL_write, %i[pointer buffer_in int], :int
        attach_function :SSL_get_error, %i[pointer int], :int
        attach_function :SSL_shutdown, [:pointer], :int
        attach_function :SSL_free, [:pointer], :void

        # @param identity [String] PSK identity
        # @param psk [String] raw pre-shared key
        # @return [FFI::Function] client callback handing +identity+ and +psk+ to OpenSSL
        # @api private
        def self.psk_callback(identity, psk)
          FFI::Function.new(:uint, %i[pointer string pointer uint pointer uint]) do |*arguments|
            _ssl, _hint, identity_out, identity_room, psk_out, psk_room = arguments
            next 0 if identity.bytesize >= identity_room || psk.bytesize > psk_room

            identity_out.put_bytes(0, "#{identity}\0")
            psk_out.put_bytes(0, psk)
            psk.bytesize
          end
        end
      end
    end
  end
end
