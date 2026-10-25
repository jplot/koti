# frozen_string_literal: true

require 'openssl'

# Mints short-lived EC certificates shaped like the bridge's: a self-signed
# root-bridge CA and leaves whose CN is a bridge id.
module TestCertificates
  private

  def certificate_authority
    key = OpenSSL::PKey::EC.generate('prime256v1')
    [certificate('/C=NL/O=Philips Hue/CN=root-bridge', key, nil, key), key]
  end

  def certificate(subject, key, issuer_cert, issuer_key)
    name = OpenSSL::X509::Name.parse(subject)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1 << 64)
    cert.subject = name
    cert.issuer = issuer_cert&.subject || name
    cert.public_key = key
    sign(cert, issuer_cert, issuer_key)
  end

  def sign(cert, issuer_cert, issuer_key)
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new(issuer_cert || cert, cert)
    cert.add_extension(extensions.create_extension('basicConstraints', issuer_cert ? 'CA:FALSE' : 'CA:TRUE', true))
    cert.sign(issuer_key, OpenSSL::Digest.new('SHA256'))
  end
end
