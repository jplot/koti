# frozen_string_literal: true

require 'json'

module Miele
  module Sdk
    module Cloud
      # An access token.
      #
      # @!attribute [r] value
      #   @return [String]
      # @!attribute [r] refresh
      #   @return [String] what renews it: the token itself on MCS, a refresh token on CIAM
      # @!attribute [r] scheme
      #   @return [String] +appToken+ (MCS) or +Bearer+ (CIAM), the scheme of the +Authorization+ header
      # @!attribute [r] created_at
      #   @return [Time]
      # @!attribute [r] expires_at
      #   @return [Time]
      Token = Data.define(:value, :refresh, :scheme, :created_at, :expires_at)

      # An access token, which the caller may save and give back.
      class Token
        # @param json [String] from {#to_json}
        # @return [Token]
        def self.from_json(json)
          fields = JSON.parse(json)
          new(value: fields.fetch('value'), refresh: fields.fetch('refresh'), scheme: fields.fetch('scheme'),
              created_at: Time.at(fields.fetch('created_at')), expires_at: Time.at(fields.fetch('expires_at')))
        end

        # @return [Token, nil] the token of +cloud_token+, else the one of +token_file+
        def self.saved
          config = Sdk.config
          file = config.token_file
          json = config.cloud_token || (File.read(file) if file && File.exist?(file))
          json && from_json(json)
        end

        # @return [Token] itself, written to +token_file+ when one is set
        def save
          file = Sdk.config.token_file
          File.open(file, 'w', 0o600) { it.write(to_json) } if file
          self
        end

        # @return [String] the token, to save and give back through +cloud_token+
        def to_json(*)
          JSON.generate(value:, refresh:, scheme:, created_at: created_at.to_i, expires_at: expires_at.to_i)
        end

        # The app renews an MCS token past half its life, a CIAM one past 90 % of it.
        #
        # @param now [Time]
        # @return [Boolean]
        def due?(now) = now >= created_at + ((expires_at - created_at) * (scheme == 'Bearer' ? 0.9 : 0.5))
      end
    end
  end
end
