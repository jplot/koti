# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # The Miele account's token, obtained and renewed the way the Miele app does it.
      class Session
        include Logout
        include Renewal

        REDIRECT = 'miele://oauth2-code/'
        private_constant :REDIRECT

        SCOPE = 'openid bpdata mcs shop zuora'
        private_constant :SCOPE

        # Refit's SystemTextJsonContentSerializer names the charset, and the app's MCS clients accept JSON
        # (ApiClientFactory.CreateApiClient).
        MCS_JSON = { 'Content-Type' => 'application/json; charset=utf-8', 'Accept' => 'application/json' }.freeze
        private_constant :MCS_JSON

        # @return [Token, nil] the current token, nil before a login
        attr_reader :token

        # @return [Locales::Organization]
        attr_reader :organization

        # @param organization [Locales::Organization] the account's organization
        # @param clock [#call] gives the current time
        # @param sleeper [#call] waits the given number of seconds
        def initialize(organization, clock: -> { Time.now }, sleeper: method(:sleep))
          @organization = organization
          @clock = clock
          @sleeper = sleeper
          @mutex = Mutex.new
          @token = Token.saved
        end

        # Logs in with the account's e-mail and password (MCS).
        #
        # @return [Token]
        # @raise [ConfigurationError] without an e-mail and a password
        # @raise [AuthenticationError] if the cloud refuses them
        # @api public
        def login
          if @organization.ciam
            raise ConfigurationError, "#{@organization.iso} accounts log in through CIAM: open authorize_url, " \
                                      'then give the code to exchange'
          end

          config = Sdk.config
          email = config.email
          password = config.password
          raise ConfigurationError, 'email and password are needed to log in' unless email && password

          url = "#{@organization.rest}/V3/Login?org=#{@organization.iso}"
          @token = mcs_token(mcs_post(url, JSON.generate(email:, password:))).save
        end

        # The cloud answers 500 to an MCS request without one. The app sends its phone's locale; the gem has none
        # and names English in the account's country.
        #
        # @return [String] the +Accept-Language+ of MCS requests
        # @api private
        def language = "en-#{@organization.iso}"

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
          @token = ciam_token(ciam_post(form)).save
        end

        # @return [String] the +Authorization+ header, after a login or a renewal when one is due
        # @api public
        def authorization = current.then { "#{it.scheme} #{it.value}" }

        # @return [Token] the token to send, after a login or a renewal when one is due
        # @api public
        def current
          token = @token || @mutex.synchronize { @token || login }
          token.due?(@clock.call) ? renew(token) : token
        end

        private

        # @return [Hash{String=>Object}]
        def mcs_post(url, body, headers = {})
          post(url, body, MCS_JSON.fetch('Content-Type'), { **MCS_JSON, 'Accept-Language' => language, **headers })
        end

        # The app's OAuth2Authenticator.RequestAccessTokenAsync takes a 400 invalid_grant for a 401.
        #
        # @param form [String]
        # @return [Hash{String=>Object}]
        def ciam_post(form) = post(endpoint('token'), form, 'application/x-www-form-urlencoded') { invalid_grant?(it) }

        # @param answer [Http::Response]
        # @return [Boolean]
        def invalid_grant?(answer)
          return false unless answer.status == 400

          body = answer.body
          fields = body.include?('{') ? JSON.parse(body) : URI.decode_www_form(body).to_h
          fields.is_a?(Hash) && fields['error'].to_s.casecmp?('invalid_grant')
        rescue JSON::ParserError, ArgumentError
          false
        end

        # @param url [String]
        # @param body [String]
        # @param type [String] the +Content-Type+
        # @param headers [Hash{String=>String}]
        # @yieldparam answer [Http::Response]
        # @yieldreturn [Boolean] whether the answer refuses the account too
        # @return [Hash{String=>Object}]
        # @raise [AuthenticationError] on 401
        # @raise [ResponseError] on any other error status
        def post(url, body, type, headers = {})
          headers = { 'Content-Type' => type, **headers }
          answer = Http.request(:post, url, headers:, body:)
          refused = answer.status == 401 || (block_given? && yield(answer))
          raise AuthenticationError, 'the Miele cloud refused the account' if refused
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
        def endpoint(type)
          @organization.ciam_endpoints.fetch(type) do
            raise ConfigurationError, "no CIAM #{type} address for #{@organization.iso}"
          end
        end
      end
    end
  end
end
