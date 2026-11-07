# frozen_string_literal: true

require 'json'

module Hue
  module Sdk
    module Secure
      # An access token of the Hue account.
      #
      # @!attribute [r] value
      #   @return [String]
      # @!attribute [r] refresh
      #   @return [String, nil] what renews it
      # @!attribute [r] created_at
      #   @return [Time]
      # @!attribute [r] expires_at
      #   @return [Time]
      Token = Data.define(:value, :refresh, :created_at, :expires_at)

      # An access token of the Hue account, which the caller may save and give back.
      class Token
        # @param json [String] from {#to_json}
        # @return [Token]
        # @api public
        def self.from_json(json)
          fields = JSON.parse(json)
          new(value: fields.fetch('value'), refresh: fields['refresh'], created_at: Time.at(fields.fetch('created_at')),
              expires_at: Time.at(fields.fetch('expires_at')))
        end

        # @return [Token, nil] the token of the +token+ setting, else the one of +token_file+
        # @api public
        def self.saved
          config = Secure.config
          file = config.token_file
          json = config.token || (File.read(file) if file && File.exist?(file))
          json && from_json(json)
        end

        # Auth0 rotates the refresh token on each renewal: a +token+ setting the caller gave follows, for the caller to
        # save it again.
        #
        # @return [Token] itself, in the +token+ setting when one is set, and written to +token_file+ when one is set
        # @api public
        def save
          config = Secure.config
          config.token &&= to_json
          file = config.token_file
          write(file) if file
          self
        end

        # @return [String] the token, to save and give back through the +token+ setting
        # @api public
        def to_json(*)
          JSON.generate(value:, refresh:, created_at: created_at.to_i, expires_at: expires_at.to_i)
        end

        # Written aside, then renamed over: a crash leaves the former file whole, and the new one is in mode 0600 even
        # when the former was not.
        #
        # @param file [String]
        # @return [void]
        # @api private
        def write(file)
          aside = "#{file}.#{Process.pid}"
          File.open(aside, 'w', 0o600) { it.write(to_json) }
          File.rename(aside, file)
        end

        # The app renews a token that expires in less than 30 s before it connects to MQTT.
        #
        # @param now [Time]
        # @return [Boolean]
        # @api public
        def due?(now) = now >= expires_at - 30
      end
    end
  end
end
