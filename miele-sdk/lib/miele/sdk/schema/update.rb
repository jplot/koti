# frozen_string_literal: true

module Miele
  module Sdk
    module Schema
      # Software update state of a Wi-Fi module, from its +/Update/+ (Miele app class +ModuleUpdateInfoDto+;
      # +release_notes+ comes from +CheckUpdateResponseBodyDto+, its class for the same answer over Bluetooth).
      #
      # @!attribute [r] newer_available
      #   @return [Boolean]
      # @!attribute [r] current_version
      #   @return [String, nil]
      # @!attribute [r] available_version
      #   @return [String, nil]
      # @!attribute [r] type
      #   @return [String, nil]
      # @!attribute [r] release_notes
      #   @return [String, nil]
      # @!attribute [r] update_in_progress
      #   @return [Boolean]
      ModuleUpdateInfo = Data.define(:newer_available, :current_version, :available_version, :type, :release_notes,
                                     :update_in_progress) do
        include Value

        optional :current_version, :available_version, :type, :release_notes
      end
    end
  end
end
