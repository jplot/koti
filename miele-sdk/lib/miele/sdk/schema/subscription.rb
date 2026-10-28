# frozen_string_literal: true

module Miele
  module Sdk
    module Schema
      # A resource an appliance is asked to push, posted to its +/Subscriptions+ (Miele app class
      # +SubscriptionDto+).
      #
      # @!attribute [r] resource
      #   @return [String, nil] path of the resource
      # @!attribute [r] callback
      #   @return [String, nil] URL the appliance posts each change to
      Subscription = Data.define(:resource, :callback) do
        include Value

        optional(*members)
      end
    end
  end
end
