# frozen_string_literal: true

module Miele
  module Sdk
    module Cloud
      class Session
        # The app's session loss (AccessTokenService.InvalidateAccessTokenAsync): it asks the cloud to end the token,
        # then forgets it, refresh token included.
        module Logout
          # Logs out and forgets the token unless another thread already replaced +refused+: the next request logs
          # in again.
          #
          # @param refused [Token]
          # @return [void]
          # @api public
          def invalidate(refused)
            @mutex.synchronize do
              next unless @token.equal?(refused)

              lose(refused)
            end
          end

          private

          # @param token [Token]
          # @return [void]
          def lose(token)
            logout(token)
            @token = nil
            Token.forget
          end

          # The app only logs a failed logout (McsModule and GigyaModule InvalidateTokenAsync).
          #
          # @param token [Token]
          # @return [void]
          def logout(token)
            token.scheme == 'Bearer' ? ciam_logout(token) : mcs_logout(token)
          rescue ConnectionError
            nil
          end

          # The app's MCS clients send a request once more after a 401 (Miele.Libraries.Session AuthenticationHandler).
          #
          # @param token [Token]
          # @return [void]
          def mcs_logout(token)
            logout_post(token) if logout_post(token).status == 401
          end

          # @param token [Token]
          # @return [Http::Response]
          def logout_post(token)
            headers = { **MCS_JSON, 'Authorization' => "appToken #{token.value}", 'Accept-Language' => language }
            Http.request(:post, "#{@organization.rest}/V2/Logout", headers:, body: '{}')
          end

          # @param token [Token]
          # @return [void]
          def ciam_logout(token)
            url = @organization.ciam_endpoints['logout']
            Http.request(:post, url, headers: { 'Authorization' => "Bearer #{token.value}" }) if url
          end
        end
      end
    end
  end
end
