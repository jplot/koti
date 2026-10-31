# frozen_string_literal: true

require 'openssl'

# A self-signed certificate for 127.0.0.1: FakeWebsocket serves wss:// with it, and a spec trusts it through
# SSLContext#cert_store.
module FakeCertificate
  def self.key = @key ||= OpenSSL::PKey::EC.generate('prime256v1')

  def self.certificate
    @certificate ||= OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      sign(cert)
    end
  end

  def self.sign(cert)
    cert.public_key = key
    cert.add_extension(OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'IP:127.0.0.1'))
    cert.sign(key, 'SHA256')
  end

  def self.trust_store = OpenSSL::X509::Store.new.tap { it.add_cert(certificate) }
end
