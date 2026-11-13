# frozen_string_literal: true

require 'openssl'

module Hue
  module Sdk
    module Secure
      # A passphrase that does not open the home, or media that does not decrypt or verify.
      class E2eeError < Error; end

      # The end-to-end encryption of Hue Secure media, as the app's +key_derivation.dart+ and envelope decrypters do
      # it: keys from the home's passphrase, the key envelope a camera seals for the app, and the AES-GCM box of an
      # image or a sample. Never tested on a device.
      module E2ee
        # The curve of every key.
        GROUP = OpenSSL::PKey::EC::Group.new('prime256v1')

        # The old envelope: three key hashes, the ephemeral key, the sealed content key and its 4-byte CCM tag.
        ENVELOPE = 244
        private_constant :ENVELOPE

        # The keys the passphrase of a home gives, as the app derives them; +inspect+ shows none of them.
        class Keys
          # @return [OpenSSL::PKey::EC] the app key, the same on every phone that knows the passphrase
          attr_reader :app

          # @return [OpenSSL::PKey::EC] the key whose public half the key service publishes for the home
          attr_reader :home_signing

          # @param passphrase [String] the five words, exactly as the app was given them
          def initialize(passphrase)
            @master = OpenSSL::KDF.pbkdf2_hmac(passphrase.b, salt: 'PhilipsHueSalt002', iterations: 10_000,
                                                             length: 32, hash: 'SHA256')
            @app = E2ee.key(@master, "\x01".b)
            @home_signing = E2ee.key(@master, "\x03".b)
          end

          # @param id [String] the camera's id in the cloud
          # @return [OpenSSL::PKey::EC] the camera's key
          def camera(id) = E2ee.key(@master, "\x02#{id}".b)

          # @return [String]
          def inspect = "#<#{self.class.name}>"
        end

        module_function

        # @param master [String] the key PBKDF2 gives
        # @param info [String] what the key is for
        # @return [OpenSSL::PKey::EC] the private key whose scalar HKDF gives
        # @api private
        def key(master, info)
          okm = OpenSSL::KDF.hkdf(master, salt: 'PhilipsHueSalt003', info:, length: 32, hash: 'SHA256')
          scalar = OpenSSL::BN.new(okm, 2) % GROUP.order
          generator = GROUP.generator #: OpenSSL::PKey::EC::Point
          point = generator.mul(scalar).to_octet_string(:uncompressed)
          fields = [OpenSSL::ASN1::Integer(1), OpenSSL::ASN1::OctetString(scalar.to_s(2).rjust(32, "\0")),
                    OpenSSL::ASN1::ObjectId('prime256v1', 0, :EXPLICIT), OpenSSL::ASN1::BitString(point, 1, :EXPLICIT)]
          OpenSSL::PKey::EC.new(OpenSSL::ASN1::Sequence(fields).to_der)
        end

        # @param key [OpenSSL::PKey::EC]
        # @return [String] the public point as the app writes it: X and Y on 32 bytes each
        # @api private
        def raw(key)
          point = key.public_key #: OpenSSL::PKey::EC::Point
          point.to_octet_string(:uncompressed).byteslice(1, 64).to_s
        end

        # Opens the key envelope a camera sealed for the app.
        #
        # @param blob [String] the envelope, and what follows it
        # @param keys [Keys]
        # @param camera_id [String]
        # @return [Array(String, String)] the content key and what follows the envelope
        # @raise [E2eeError] if the envelope is post-quantum, is not for this app or camera, or does not verify
        # @api private
        def open(blob, keys:, camera_id:)
          blob = blob.b
          camera = keys.camera(camera_id)
          check(blob, keys.app, camera)
          plain = sealed(blob, keys.app, camera_id)
          cek = plain.byteslice(0, 16).to_s
          raise E2eeError, 'the content key signature does not verify' unless verified?(camera, cek, plain[16, 64])

          [cek, blob.byteslice(ENVELOPE..).to_s]
        end

        # Decrypts a box: a 12-byte nonce, the ciphertext and a 16-byte tag, with no additional data.
        #
        # @param cek [String] the content key
        # @param box [String]
        # @return [String]
        # @raise [E2eeError] if the box does not decrypt
        # @api private
        def decrypt(cek, box)
          raise E2eeError, 'the media does not decrypt' if box.bytesize < 28

          cipher = gcm(cek, box.byteslice(0, 12).to_s, box.byteslice(-16, 16).to_s)
          cipher.update(box.byteslice(12, box.bytesize - 28).to_s) + cipher.final
        rescue OpenSSL::Cipher::CipherError
          raise E2eeError, 'the media does not decrypt'
        end

        def gcm(key, nonce, tag)
          OpenSSL::Cipher.new("aes-#{key.bytesize * 8}-gcm").decrypt.tap do |cipher|
            cipher.key = key
            cipher.iv = nonce
            cipher.auth_tag = tag
            cipher.auth_data = ''
          end
        end

        # A post-quantum envelope starts with its TLV header (tag 0, 64 bytes), which the app reads only when a
        # remote toggle, off by default, has given it an ML-KEM key.
        def check(blob, app, camera)
          if blob.start_with?([0, 64].pack('CN'))
            raise E2eeError, "a post-quantum envelope needs ML-KEM, which Ruby's OpenSSL cannot open"
          end
          raise E2eeError, 'the envelope is cut short' if blob.bytesize < ENVELOPE
          raise E2eeError, 'the envelope is not for this app' unless blob.byteslice(32, 32) == digest(app)
          raise E2eeError, 'the envelope is not from this camera' unless blob.byteslice(64, 32) == digest(camera)
        end

        def sealed(blob, app, camera_id)
          ephemeral = blob.byteslice(96, 64).to_s
          okm = OpenSSL::KDF.hkdf(ephemeral + app.derive(public_key(ephemeral)), salt: 'HueSalt001',
                                                                                 info: camera_id.b, length: 29,
                                                                                 hash: 'SHA256')
          ccm(okm.byteslice(0, 16).to_s, okm.byteslice(16, 13).to_s, blob.byteslice(160, 80).to_s,
              blob.byteslice(240, 4).to_s)
        end

        def ccm(key, nonce, ciphertext, tag)
          cipher = OpenSSL::Cipher.new('aes-128-ccm').decrypt
          cipher.iv_len = 13
          cipher.auth_tag_len = 4
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_tag = tag
          cipher.ccm_data_len = ciphertext.bytesize
          cipher.update(ciphertext)
        rescue OpenSSL::Cipher::CipherError
          raise E2eeError, 'the envelope does not decrypt'
        end

        def public_key(raw)
          point = OpenSSL::PKey::EC::Point.new(GROUP, OpenSSL::BN.new("\x04".b + raw, 2))
          algorithm = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::ObjectId('id-ecPublicKey'),
                                               OpenSSL::ASN1::ObjectId('prime256v1')])
          bits = OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed))
          OpenSSL::PKey::EC.new(OpenSSL::ASN1::Sequence([algorithm, bits]).to_der)
        rescue OpenSSL::PKey::EC::Point::Error, OpenSSL::PKey::PKeyError
          raise E2eeError, 'the envelope holds no key of the curve'
        end

        def verified?(key, data, signature)
          pair = [0, 32].map { OpenSSL::ASN1::Integer(OpenSSL::BN.new(signature.to_s.byteslice(it, 32).to_s, 2)) }
          key.verify(OpenSSL::Digest.new('SHA256'), OpenSSL::ASN1::Sequence(pair).to_der, data)
        end

        def digest(key) = OpenSSL::Digest::SHA256.digest(raw(key))

        private_class_method :gcm, :check, :sealed, :ccm, :public_key, :verified?, :digest
      end
    end
  end
end
