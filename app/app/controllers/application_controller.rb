# frozen_string_literal: true

# Base of every koti web controller: a JSON API, no views.
class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Authentication

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def not_found = head(:not_found)
end
