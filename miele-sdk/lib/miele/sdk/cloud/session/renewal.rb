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
        end
      end
    end
  end
end
