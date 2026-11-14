# frozen_string_literal: true

require 'erb'

# The signature of a presigned signaling URL as the app's own SigV4 code computes it (inv. §1.2, step 4), written
# without the aws-sigv4 gem the gem signs with.
module AppSigv4
  module_function

  def signature(url, secret:)
    uri = URI(url)
    params = URI.decode_www_form(uri.query.to_s).to_h
    scope = params.fetch('X-Amz-Credential').split('/', 2).last
    signed = "AWS4-HMAC-SHA256\n#{params.fetch('X-Amz-Date')}\n#{scope}\n#{sha256(canonical(uri.host, params))}"
    hmac(key(secret, scope), signed).unpack1('H*')
  end

  def canonical(host, params)
    query = params.except('X-Amz-Signature').sort.map { |name, value| "#{escape(name)}=#{escape(value)}" }.join('&')
    "GET\n/\n#{query}\nhost:#{host}\n\nhost\n#{sha256('')}"
  end

  def key(secret, scope) = scope.split('/').reduce("AWS4#{secret}") { |key, part| hmac(key, part) }

  def hmac(key, data) = OpenSSL::HMAC.digest('SHA256', key, data)

  def sha256(data) = OpenSSL::Digest::SHA256.hexdigest(data)

  def escape(text) = ERB::Util.url_encode(text)
end
