# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # The Miele account's token, obtained and renewed the way the Miele app does it.
      class Session
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

        REDIRECT = 'miele://oauth2-code/'
        private_constant :REDIRECT

        SCOPE = 'openid bpdata mcs shop zuora'
        private_constant :SCOPE

        # @return [Token, nil] the current token, nil before a login
        attr_reader :token

        # @param organization [Locales::Organization] the account's organization
        # @param clock [#call] gives the current time
        # @param sleeper [#call] waits the given number of seconds
        def initialize(organization, clock: -> { Time.now }, sleeper: method(:sleep))
          @organization = organization
          @clock = clock
          @sleeper = sleeper
          @mutex = Mutex.new
          saved = Sdk.config.cloud_token
          @token = saved && Token.from_json(saved)
        end

        # Logs in with the account's e-mail and password (MCS).
        #
        # @return [Token]
        # @raise [ConfigurationError] without an e-mail and a password
        # @raise [AuthenticationError] if the cloud refuses them
        # @api public
        def login
          config = Sdk.config
          email = config.email
          password = config.password
          raise ConfigurationError, 'email and password are needed to log in' unless email && password

          url = "#{@organization.rest}/V3/Login?org=#{@organization.iso}"
          @token = mcs_token(post(url, JSON.generate(email:, password:), 'application/json'))
        end

        # @return [String] the page that gives a CIAM code once the account logs in on it
        # @raise [ConfigurationError] without +ciam_client_id+
        # @api public
        def authorize_url
          state = SecureRandom.hex(16).upcase.scan(/../).join('-')
          query = URI.encode_www_form(client_id:, scope: SCOPE, state:, response_type: 'code', redirect_uri: REDIRECT)
          "#{endpoint('authorize')}?#{query}"
        end

        # @param code [String] the +code+ of the +miele://oauth2-code/+ address the CIAM page redirects to
        # @return [Token]
        # @raise [ConfigurationError] without +ciam_client_id+
        # @api public
        def exchange(code)
          form = URI.encode_www_form(grant_type: 'authorization_code', code:, redirect_uri: REDIRECT, client_id:)
          @token = ciam_token(post(endpoint('token'), form, 'application/x-www-form-urlencoded'))
        end

        # @return [String] the +Authorization+ header, after a login or a renewal when one is due
        # @api public
        def authorization
          current = @token || @mutex.synchronize { @token || login }
          current = renew(current) if current.due?(@clock.call)
          "#{current.scheme} #{current.value}"
        end

        # Renews the token unless another thread already did since +expired+ was read.
        #
        # @param expired [Token]
        # @return [Token]
        # @api public
        def renew(expired)
          @mutex.synchronize do
            @token = refreshed(expired) if @token.equal?(expired)
            @token or raise AuthenticationError, 'no token to renew'
          end
        end

        private

        # Like the app: three attempts a second apart, and a new login when the cloud refuses the renewal.
        #
        # @param expired [Token]
        # @return [Token]
        def refreshed(expired)
          three_times { expired.scheme == 'Bearer' ? ciam_refresh(expired) : mcs_refresh(expired) }
        rescue AuthenticationError
          raise unless expired.scheme == 'appToken' && Sdk.config.email

          login
        end

        # @yieldreturn [Token]
        # @return [Token]
        def three_times
          attempts = 0
          begin
            yield
          rescue ConnectionError, ResponseError
            raise if (attempts += 1) == 3

            @sleeper.call(1)
            retry
          end
        end

        # @param expired [Token]
        # @return [Token]
        def mcs_refresh(expired)
          url = "#{@organization.rest}/V2/AppTokenRefresh"
          mcs_token(post(url, '{}', 'application/json', authorization: "appToken #{expired.value}"))
        end

        # @param expired [Token]
        # @return [Token]
        def ciam_refresh(expired)
          form = URI.encode_www_form(refresh_token: expired.refresh, client_id:, grant_type: 'refresh_token',
                                     client_secret: '')
          ciam_token(post(endpoint('token'), form, 'application/x-www-form-urlencoded'))
        end

        # @param url [String]
        # @param body [String]
        # @param type [String] the +Content-Type+
        # @param authorization [String, nil]
        # @return [Hash{String=>Object}]
        # @raise [AuthenticationError] on 401
        # @raise [ResponseError] on any other error status
        def post(url, body, type, authorization: nil)
          headers = { 'Content-Type' => type, 'Authorization' => authorization }.compact
          answer = Http.request(:post, url, headers:, body:)
          raise AuthenticationError, 'the Miele cloud refused the account' if answer.status == 401
          unless answer.status.between?(200, 299)
            raise ResponseError.new(answer.status, "cloud answered #{answer.status}")
          end

          JSON.parse(answer.body)
        end

        # @param answer [Hash] +appToken+ and +appTokenValidity+, the Unix time it expires at
        # @return [Token]
        def mcs_token(answer)
          value = answer.fetch('appToken')
          Token.new(value:, refresh: value, scheme: 'appToken', created_at: @clock.call,
                    expires_at: Time.at(answer.fetch('appTokenValidity')))
        end

        # @param answer [Hash] +access_token+, +refresh_token+ and +expires_in+, in seconds
        # @return [Token]
        def ciam_token(answer)
          now = @clock.call
          Token.new(value: answer.fetch('access_token'), refresh: answer.fetch('refresh_token'), scheme: 'Bearer',
                    created_at: now, expires_at: now + answer.fetch('expires_in'))
        end

        # @return [String]
        # @raise [ConfigurationError]
        def client_id = Sdk.config.ciam_client_id || raise(ConfigurationError, 'ciam_client_id is needed for CIAM')

        # @param type [String]
        # @return [String]
        def endpoint(type) = @organization.ciam_endpoints.fetch(type)
      end
    end
  end
end
