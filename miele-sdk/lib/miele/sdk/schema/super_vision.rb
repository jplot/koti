# frozen_string_literal: true

module Miele
  module Sdk
    module Schema
      # The peers an appliance notifies, from its +SuperVision+ (Miele app class +SuperVisionDto+).
      #
      # @!attribute [r] enabled
      #   @return [Boolean]
      # @!attribute [r] error_only
      #   @return [Boolean]
      # @!attribute [r] entries
      #   @return [Hash{String=>Object}] the other keys: a link to each peer, by fabrication number
      SuperVision = Data.define(:enabled, :error_only, :entries) do
        include Value

        extension :entries
      end

      # A peer shown in, or hidden from, an appliance's +SuperVision+ (Miele app class
      # +SuperVisionDeviceDto+).
      #
      # @!attribute [r] show
      #   @return [Boolean]
      # @!attribute [r] signal
      #   @return [Boolean, nil]
      SuperVisionDevice = Data.define(:show, :signal) do
        include Value

        optional :signal
      end
    end
  end
end
