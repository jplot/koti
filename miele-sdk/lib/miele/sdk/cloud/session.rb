# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'uri'

module Miele
  module Sdk
    module Cloud
      # The Miele account's token, obtained and renewed the way the Miele app does it.
      class Session
        REDIRECT = 'miele://oauth2-code/'
        private_constant :REDIRECT

        SCOPE = 'openid bpdata mcs shop zuora'
        private_constant :SCOPE

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
          @token = ciam_token(post(endpoint('token'), form, 'application/x-www-form-urlencoded')).save
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

        # Renews the token unless another thread already did since +expired+ was read. A stopped event stream
        # kills its thread: the kill waits for the renewal, which the cloud may have done already, and for its
        # file, which it would leave empty.
        #
        # @param expired [Token]
        # @return [Token]
        # @api public
        def renew(expired) = Thread.handle_interrupt(Object => :never) { @mutex.synchronize { replaced(expired) } }

        private

        # @param expired [Token]
        # @return [Token]
        def replaced(expired)
          @token = refreshed(expired).save if @token.equal?(expired)
          @token or raise AuthenticationError, 'no token to renew'
        end

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
          mcs_token(mcs_post(url, '{}', 'Authorization' => "appToken #{expired.value}"))
        end

        # @param expired [Token]
        # @return [Token]
        def ciam_refresh(expired)
          form = URI.encode_www_form(refresh_token: expired.refresh, client_id:, grant_type: 'refresh_token',
                                     client_secret: '')
          ciam_token(post(endpoint('token'), form, 'application/x-www-form-urlencoded'))
        end

        # @return [Hash{String=>Object}]
        def mcs_post(url, body, headers = {})
          post(url, body, 'application/json', { 'Accept-Language' => language, **headers })
        end

        # @param url [String]
        # @param body [String]
        # @param type [String] the +Content-Type+
        # @param headers [Hash{String=>String}]
        # @return [Hash{String=>Object}]
        # @raise [AuthenticationError] on 401
        # @raise [ResponseError] on any other error status
        def post(url, body, type, headers = {})
          headers = { 'Content-Type' => type, **headers }
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
        def endpoint(type)
          @organization.ciam_endpoints.fetch(type) do
            raise ConfigurationError, "no CIAM #{type} address for #{@organization.iso}"
          end
        end
      end
    end
  end
end
