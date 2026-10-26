# frozen_string_literal: true

require 'digest'
require 'rotp'

module Ajax
  module Sdk
    module Cloud
      # Holds the account's login session: it signs in with the password hash, answers the two-factor
      # challenge when the gateway asks for it, keeps the session token and user id, and builds the
      # metadata the gateway expects on every call. Login answers arrive as Hashes (see {Client}).
      class Session
        GATEWAY = 'systems.ajax.api.ecosystem.v3.mobilegwsvc.service'
        PASSWORD = "/#{GATEWAY}.login_by_password.LoginByPasswordService/execute".freeze
        TOTP = "/#{GATEWAY}.login_by_totp.LoginByTotpService/execute".freeze
        ROLE = :USER_ROLE_USER
        REASONS = %i[invalid_credentials account_locked account_not_confirmed invalid_totp bad_request].freeze
        private_constant :GATEWAY, :PASSWORD, :TOTP, :ROLE, :REASONS

        # @param client [Client] the gRPC client used to send the login calls
        # @param settings [Configuration::Settings]
        # @api private
        def initialize(client, settings)
          @client = client
          @settings = settings
          @token = settings.session_token
          @user_id = settings.user_id
        end

        # @return [void] log in only if there is no session yet
        def ensure_login
          login unless @token && @user_id
        end

        # Signs in with the password hash, then with the TOTP code when two-factor is required.
        #
        # @return [void]
        # @raise [AuthenticationError] when the gateway refuses the login
        def login
          failure = sign_in(PASSWORD, password_request) or return
          return login_with_totp(failure.dig(:two_fa_required, :request_id)) if failure[:two_fa_required]

          raise AuthenticationError.new(reason(failure), "login refused, #{failure[:attempts_left]} attempts left")
        end

        # @return [Hash{String=>String}] the app metadata, plus the session metadata once logged in
        def metadata
          base = app_metadata
          token = @token or return base

          base.merge('client-session-token' => token, 'a911-user-id' => @user_id.to_s,
                     'client-user-role' => 'USER', 'client-user-login' => @settings.email.to_s)
        end

        private

        # @return [Hash, nil] the failure Hash, or nil once the session is accepted
        def sign_in(path, request)
          answer = @client.authenticate(path, request, app_metadata)
          return accept(answer[:success]) if answer[:success]

          answer[:failure]
        end

        def login_with_totp(request_id, retried: false)
          failure = sign_in(TOTP, totp_request(request_id, retried)) or return
          return login_with_totp(request_id, retried: true) if failure[:invalid_totp] && !retried

          raise AuthenticationError.new(reason(failure), 'two-factor login refused')
        end

        def accept(success)
          @token = success[:session_token].unpack1('H*').upcase
          @user_id = success.dig(:lite_account, :user_hex_id)
          nil
        end

        def password_request
          { email: @settings.email, password_sha256_hash: password_hash, user_role: ROLE }
        end

        def totp_request(request_id, retried)
          code = ROTP::TOTP.new(@settings.totp_secret.to_s).at(Time.now + (retried ? 30 : 0))
          { email: @settings.email, user_role: ROLE, request_id:, totp: code }
        end

        def password_hash
          @settings.password_sha256 || Digest::SHA256.hexdigest(@settings.password.to_s)
        end

        def reason(failure) = (REASONS & failure.keys).first || :bad_request

        def app_metadata
          { 'client-device-id' => @settings.client_device_id, 'client-device-model' => @settings.client_device_model,
            'client-version-major' => @settings.client_version.split('.').first.to_s, 'client-os' => 'Android',
            'application-label' => 'Ajax', 'client-device-type' => 'MOBILE' }
        end
      end
    end
  end
end
