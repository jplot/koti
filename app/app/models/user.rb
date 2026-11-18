# frozen_string_literal: true

# An account that can sign in to koti. Accounts are created from the console.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
