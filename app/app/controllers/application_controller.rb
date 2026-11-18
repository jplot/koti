# frozen_string_literal: true

# Base of every koti web controller: a JSON API, no views.
class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Authentication
end
