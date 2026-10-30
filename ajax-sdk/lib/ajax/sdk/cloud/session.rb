# frozen_string_literal: true

require 'digest'
require 'rotp'
require_relative 'values'

module Ajax
  module Sdk
    module Cloud
      # Holds the account's login session: it signs in with the password hash, answers the two-factor
      # challenge when the gateway asks for it, keeps the session token and user id, and builds the
      # metadata the gateway expects on every call. Login answers arrive whole, success and failure (see {Client}).
      class Session
        GATEWAY = 'systems.ajax.api.ecosystem.v3.mobilegwsvc.service'
        PASSWORD = "/#{GATEWAY}.login_by_password.LoginByPasswordService/execute".freeze
        TOTP = "/#{GATEWAY}.login_by_totp.LoginByTotpService/execute".freeze
        LOGIN = Messages::Api::Ecosystem::V3::Mobilegwsvc::Service
        private_constant :GATEWAY, :PASSWORD, :TOTP, :LOGIN

        # @param client [Client] the gRPC client used to send the login calls
        # @param settings [Configuration::Settings]
        # @api private
        def initialize(client, settings)
          @client = client
          @settings = settings
          @token = settings.session_token
          @user_id = settings.user_id
          @mutex = Mutex.new
        end

        # @return [String] a description that never prints the token or the account's secrets
        def inspect = "#<#{self.class.name} logged_in=#{!@token.nil?}>"

        # @return [void] log in only if there is no session yet; concurrent callers log in once
        def ensure_login
          @mutex.synchronize { sign_in_flow unless @token && @user_id }
        end

        # Signs in with the password hash, then with the TOTP code when two-factor is required.
        #
        # @param expired [String, nil] the session token the gateway refused: another thread that already replaced
        #   it leaves nothing to do
        # @return [void]
        # @raise [AuthenticationError] when the gateway refuses the login
        def login(expired = @token)
          @mutex.synchronize { sign_in_flow if @token == expired }
        end

        # @return [Hash{String=>String}] the app metadata, plus the session metadata once logged in
        def metadata
          base = app_metadata
          token = @token or return base

          base.merge('client-session-token' => token, 'a911-user-id' => @user_id.to_s,
                     'client-user-role' => 'USER', 'client-user-login' => @settings.email.to_s)
        end

        private

        def sign_in_flow
          require_credentials
          failure = sign_in(PASSWORD, password_request) or return
          return two_factor(failure.two_fa_required.request_id) if failure.two_fa_required

          raise AuthenticationError.new(reason(failure), "login refused, #{failure.attempts_left} attempts left")
        end

        def require_credentials
          return unless @settings.password_sha256.nil? && @settings.password.nil?

          raise ConfigurationError, 'set password or password_sha256'
        end

        # Raises rather than send an empty TOTP that only burns a login attempt.
        def two_factor(request_id)
          raise AuthenticationError.new(:two_fa_required, 'no totp_secret set') if @settings.totp_secret.nil?

          login_with_totp(request_id)
        end

        # @return [Data, nil] the failure, or nil once the session is accepted
        def sign_in(path, request)
          answer = @client.authenticate(path, request, app_metadata)
          return accept(answer.success) if answer.success

          answer.failure
        end

        def login_with_totp(request_id, sent = nil)
          code = totp_code(sent)
          failure = sign_in(TOTP, totp_request(request_id, code)) or return
          return login_with_totp(request_id, code) if failure.invalid_totp && sent.nil?

          raise AuthenticationError.new(reason(failure), 'two-factor login refused')
        end

        # A refused code that has since expired gives way to the current one; one still current gives
        # way to the next window's, for a gateway whose clock runs ahead.
        def totp_code(sent)
          totp = ROTP::TOTP.new(@settings.totp_secret.to_s)
          now = Time.now
          code = totp.at(now)
          code == sent ? totp.at(now + 30) : code
        end

        def accept(success)
          @token = success.session_token.unpack1('H*').upcase
          @user_id = success.lite_account&.user_hex_id
          nil
        end

        def password_request
          LOGIN::LoginByPassword::LoginByPasswordRequest.new(email: @settings.email.to_s, user_role: :user,
                                                             password_sha256_hash: password_hash)
        end

        def totp_request(request_id, totp)
          LOGIN::LoginByTotp::LoginByTotpRequest.new(email: @settings.email.to_s, user_role: :user, request_id:, totp:)
        end

        def password_hash
          @settings.password_sha256 || Digest::SHA256.hexdigest(@settings.password.to_s)
        end

        def reason(failure) = failure.error || :bad_request

        def app_metadata
          { 'client-device-id' => @settings.client_device_id, 'client-device-model' => @settings.client_device_model,
            'client-version-major' => @settings.client_version.split('.').first.to_s, 'client-os' => 'Android',
            'application-label' => 'Ajax', 'client-device-type' => 'MOBILE' }
        end
      end
    end
  end
end
