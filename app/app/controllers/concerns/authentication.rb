# frozen_string_literal: true

# Requires a signed-in account on every action, from the signed `session_id` cookie.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
  end

  class_methods do
    # Lets the actions named by `only:` or `except:` run without an account.
    #
    # @param options [Hash] the `only:` or `except:` option of `skip_before_action`
    # @return [void]
    def allow_unauthenticated_access(**options) = skip_before_action(:require_authentication, **options)
  end

  private

  def require_authentication = resume_session || head(:unauthorized)

  def resume_session = Current.session ||= find_session_by_cookie

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
  end

  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_addr).tap do |session|
      Current.session = session
      cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
    end
  end

  def terminate_session
    Current.session.destroy
    cookies.delete(:session_id)
  end
end
