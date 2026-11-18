# frozen_string_literal: true

# The JSON API the front calls, under /api.
module Api
  # Opens, reads and closes the session of an account.
  class SessionsController < ApplicationController
    allow_unauthenticated_access only: :create
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { render json: { error: 'rate_limited' }, status: :too_many_requests }

    # The signed-in account.
    #
    # @return [void] 200 with `email_address`
    def show = render(json: { email_address: Current.user.email_address })

    # Signs in with an address and a password.
    #
    # @return [void] 201 with `email_address`, or 401 with `error: invalid_credentials`
    def create
      if (user = User.authenticate_by(params.permit(:email_address, :password)))
        start_new_session_for user
        render json: { email_address: user.email_address }, status: :created
      else
        render json: { error: 'invalid_credentials' }, status: :unauthorized
      end
    end

    # Signs out.
    #
    # @return [void] 204
    def destroy
      terminate_session
      head :no_content
    end
  end
end
