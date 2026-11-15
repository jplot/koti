# frozen_string_literal: true

module Miele
  module Sdk
    module Cloud
      class Session
        # The token's renewal, as the app's AccessTokenService.TryGetValidAccessTokenAsync does it.
        module Renewal
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

          # A refused renewal loses the session, as in the app's AccessTokenService.TryGetValidAccessTokenAsync: no
          # new login before the next request.
          #
          # @param expired [Token]
          # @return [Token]
          def refreshed(expired)
            refresh(expired)
          rescue AuthenticationError
            lose(expired)
            raise
          end

          # Like the app: three attempts a second apart.
          #
          # @param expired [Token]
          # @return [Token]
          def refresh(expired)
            three_times { expired.scheme == 'Bearer' ? ciam_refresh(expired) : mcs_refresh(expired) }
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

          # The app's AuthenticationHandler sends a refused renewal once more, with the same persisted token
          # (TokenService.GetPersistantTokenAsync).
          #
          # @param expired [Token]
          # @return [Token]
          def mcs_refresh(expired)
            url = "#{@organization.rest}/V2/AppTokenRefresh"
            headers = { 'Authorization' => "appToken #{expired.value}" }
            answer = begin
              mcs_post(url, '{}', headers)
            rescue AuthenticationError
              mcs_post(url, '{}', headers)
            end
            mcs_token(answer)
          end

          # @param expired [Token]
          # @return [Token]
          def ciam_refresh(expired)
            form = URI.encode_www_form(refresh_token: expired.refresh, client_id:, grant_type: 'refresh_token',
                                       client_secret: '')
            ciam_token(ciam_post(form))
          end
        end
      end
    end
  end
end
