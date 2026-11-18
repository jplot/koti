# frozen_string_literal: true

# A signed-in device of an account, named by the signed `session_id` cookie.
class Session < ApplicationRecord
  belongs_to :user
end
