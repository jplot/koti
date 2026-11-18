# frozen_string_literal: true

# A home plan in the koti-plan format. Each import adds a row; the latest one is the plan.
class Plan < ApplicationRecord
  scope :latest, -> { order(id: :desc).limit(1) }

  validate { KotiPlan.errors(document).each { errors.add(:document, it) } }
end
