# frozen_string_literal: true

# Base of every koti model, stored in PostgreSQL.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
