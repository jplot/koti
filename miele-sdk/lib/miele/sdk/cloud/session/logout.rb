# frozen_string_literal: true

module Miele
  module Sdk
    module Cloud
      class Session
        # The app's session loss (AccessTokenService.InvalidateAccessTokenAsync): it asks the cloud to end the token,
        # then forgets it, refresh token included, apart from the request that found it (SafeFireAndForgetAsync).
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
          rescue Error
            nil
          end

          # The app keeps the token on any MCS failure but a refused logout (McsModule takes only Refit.ApiException).
          #
          # @param token [Token]
          # @return [void]
          def logout(token) = token.scheme == 'Bearer' ? ciam_logout(token) : mcs_logout(token)

          # The app's AuthenticationHandler sends a refused logout once more with the token TokenService.GetTokenAsync
          # gives: renewed when due; without one, the logout fails.
          #
          # @param token [Token]
          # @return [void]
          def mcs_logout(token)
            return unless logout_post(token).status == 401

            logout_post(token.due?(@clock.call) ? refresh(token) : token)
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
          rescue ConnectionError
            nil
          end
        end
      end
    end
  end
end
