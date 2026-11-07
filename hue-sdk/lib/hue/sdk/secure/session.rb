# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'uri'

module Hue
  module Sdk
    module Secure
      # The Hue account's token, obtained and renewed through Auth0 the way the Hue app does it.
      class Session
        REDIRECT = 'hue-auth0://auth.meethue.com/com.signify.hue/callback'
        private_constant :REDIRECT

        AUDIENCE = 'https://account.meethue.com'
        private_constant :AUDIENCE

        # @return [Token, nil] the current token, nil before a login
        attr_reader :token

        # @return [String, nil] the PKCE verifier of the last {#authorize_url}, to keep if the code comes back to
        #   another process
        attr_reader :verifier

        # @param clock [#call] gives the current time
        # @api public
        def initialize(clock: -> { Time.now })
          @clock = clock
          @mutex = Mutex.new
          @attempts = 0
          @token = Token.saved
        end

        # @return [String] the page that gives a code once the account logs in on it: the browser then fails to open
        #   +hue-auth0://…?code=…+, whose +code+ goes to {#exchange}
        # @raise [AuthenticationError] without +client_id+
        # @raise [ConnectionError] if the OpenID discovery cannot be reached
        # @api public
        def authorize_url
          @verifier = verifier = SecureRandom.urlsafe_base64(32)
          challenge = Digest::SHA256.base64digest(verifier).tr('+/', '-_').delete('=')
          query = URI.encode_www_form(client_id:, redirect_uri: REDIRECT, response_type: 'code',
                                      scope: 'openid profile offline_access', audience: AUDIENCE,
                                      state: SecureRandom.urlsafe_base64(16), code_challenge: challenge,
                                      code_challenge_method: 'S256')
          "#{endpoint('authorization_endpoint')}?#{query}"
        end

        # @param code [String] the +code+ of the +hue-auth0:+ address
        # @param verifier [String, nil] the {#verifier} of the address the code comes from
        # @return [Token]
        # @raise [AuthenticationError] without +client_id+, or if Auth0 refuses the code
        # @api public
        def exchange(code, verifier: self.verifier)
          @token = issued({ grant_type: 'authorization_code', client_id:, code:, code_verifier: verifier,
                            redirect_uri: REDIRECT }).save
        end

        # @return [Token] the token to send, renewed when it expires in less than 30 s
        # @raise [AuthenticationError] before a login, or if Auth0 refuses the renewal
        # @api public
        def current
          token = @token or raise AuthenticationError, 'log in first: open authorize_url, then exchange the code'
          token.due?(@clock.call) ? renew(token) : token
        end

        # Renews the token once across threads: a thread that waited on another's renewal of the same token takes its
        # token, or raises its failure, since Auth0 rotates the refresh token. A kill waits for the renewal, which
        # Auth0 may have done already, and for its file.
        #
        # @param expired [Token]
        # @return [Token]
        # @raise [AuthenticationError] if Auth0 refuses the renewal; the saved token stays
        # @api public
        def renew(expired)
          Thread.handle_interrupt(Object => :never) do
            attempts = @attempts
            @mutex.synchronize { replaced(expired, attempts) }
          end
        end

        private

        # @param expired [Token]
        # @param attempts [Integer] the renewals sent when the thread began to wait
        # @return [Token]
        def replaced(expired, attempts)
          token = @token
          return token if token && !token.equal?(expired)

          failure = @failure
          raise failure if failure && @attempts != attempts

          attempted(expired)
        end

        # @param expired [Token]
        # @return [Token]
        def attempted(expired)
          token = issued(refresh_form(expired), expired.refresh).save
          @failure = nil
          @token = token
        rescue Error => e
          @failure = e
          raise
        ensure
          @attempts += 1
        end

        # @param expired [Token]
        # @return [Hash{Symbol=>String, nil}]
        def refresh_form(expired)
          { grant_type: 'refresh_token', client_id:, refresh_token: expired.refresh, audience: AUDIENCE }
        end

        # @param form [Hash{Symbol=>String, nil}]
        # @param refresh [String, nil] kept when the answer gives no new one
        # @return [Token]
        def issued(form, refresh = nil)
          headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
          answer = Http.request(:post, endpoint('token_endpoint'), headers:, body: URI.encode_www_form(form)).body
          now = @clock.call
          Token.new(value: answer.fetch('access_token'), refresh: answer['refresh_token'] || refresh, created_at: now,
                    expires_at: now + answer.fetch('expires_in'))
        end

        # The app gives Auth0 its issuer and reads the addresses from the discovery.
        #
        # @param name [String]
        # @return [String]
        def endpoint(name)
          Http.request(:get, "#{Secure.config.login_url}/.well-known/openid-configuration").body.fetch(name)
        end

        # @return [String]
        # @raise [AuthenticationError]
        def client_id = Secure.config.client_id || raise(AuthenticationError, 'client_id is not configured')
      end
    end
  end
end
