# frozen_string_literal: true

require 'openssl'

# The camera's side of the end-to-end encryption of Hue Secure, written from the app's code (envelope, AES-GCM box)
# without the gem's E2ee, so that a slip in one cannot hide behind the same slip in the other.
class FakeCamera
  GROUP = OpenSSL::PKey::EC::Group.new('prime256v1')

  def initialize(passphrase, camera_id)
    master = OpenSSL::KDF.pbkdf2_hmac(passphrase.b, salt: 'PhilipsHueSalt002', iterations: 10_000, length: 32,
                                                    hash: 'SHA256')
    @camera_id = camera_id
    @app, @home, @device = ["\x01", "\x03", "\x02#{camera_id}"].map { private_key(master, it.b) }
  end

  def home_signing_pem = public_only(@home).public_to_pem

  def envelope(cek)
    ephemeral = OpenSSL::PKey::EC.generate('prime256v1')
    [@home, @app, @device].map { OpenSSL::Digest::SHA256.digest(raw(it)) }.join + raw(ephemeral) +
      sealed(ephemeral, cek + signature(@device, cek))
  end

  def pqc_envelope = [0, 64].pack('CN') + Random.bytes(64) + [0x10, 1336].pack('CN') + Random.bytes(1336)

  def box(cek, plain)
    cipher = OpenSSL::Cipher.new("aes-#{cek.bytesize * 8}-gcm").encrypt
    cipher.key = cek
    nonce = cipher.random_iv
    nonce + cipher.update(plain) + cipher.final + cipher.auth_tag
  end

  def snapshot_blob(image, cek) = envelope(cek) + box(cek, image)

  private

  def private_key(master, info)
    scalar = OpenSSL::BN.new(OpenSSL::KDF.hkdf(master, salt: 'PhilipsHueSalt003', info:, length: 32,
                                                       hash: 'SHA256'), 2) % GROUP.order
    point = GROUP.generator.mul(scalar)
    OpenSSL::PKey::EC.new(OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(1),
                                                   OpenSSL::ASN1::OctetString(scalar.to_s(2).rjust(32, "\0")),
                                                   OpenSSL::ASN1::ObjectId('prime256v1', 0, :EXPLICIT),
                                                   OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed), 1,
                                                                            :EXPLICIT)]).to_der)
  end

  def sealed(ephemeral, plain)
    okm = OpenSSL::KDF.hkdf(raw(ephemeral) + ephemeral.derive(public_only(@app)), salt: 'HueSalt001',
                                                                                  info: @camera_id.b, length: 29,
                                                                                  hash: 'SHA256')
    ccm(okm.byteslice(0, 16), okm.byteslice(16, 13), plain)
  end

  def public_only(key) = OpenSSL::PKey.read(key.public_to_der)

  def raw(key) = key.public_key.to_octet_string(:uncompressed).byteslice(1, 64)

  def signature(key, data)
    r, s = OpenSSL::ASN1.decode(key.sign('SHA256', data)).value.map { it.value.to_s(2).rjust(32, "\0") }
    r + s
  end

  def ccm(key, nonce, plain)
    cipher = OpenSSL::Cipher.new('aes-128-ccm').encrypt
    cipher.iv_len = 13
    cipher.auth_tag_len = 4
    cipher.key = key
    cipher.iv = nonce
    cipher.ccm_data_len = plain.bytesize
    cipher.update(plain) + cipher.final + cipher.auth_tag(4)
  end
end
