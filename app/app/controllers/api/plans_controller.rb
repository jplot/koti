# frozen_string_literal: true

module Api
  # Serves the home plan and imports a new one.
  class PlansController < ApplicationController
    # The body is the whole koti-plan document, read as is.
    wrap_parameters false

    # The latest imported plan.
    #
    # @return [void] 200 with the document, or 404 when no plan was imported
    def show = render(json: Plan.latest.first!.document)

    # Imports a plan; a refused one leaves the current plan in place.
    #
    # @return [void] 200 with the document, or 422 with `errors`
    def update
      plan = Plan.new(document: JSON.parse(request.raw_post))
      if plan.save
        render json: plan.document
      else
        render json: { errors: plan.errors[:document] }, status: :unprocessable_content
      end
    rescue JSON::ParserError
      render json: { errors: ['body is not JSON'] }, status: :unprocessable_content
    end
  end
end
