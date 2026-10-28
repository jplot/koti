# frozen_string_literal: true

module Miele
  module Sdk
    module Schema
      # Label of an appliance in its +Ident+ (Miele app class +DeviceIdentificationLabelDto+).
      #
      # @!attribute [r] version
      #   @return [String, nil]
      # @!attribute [r] fab_number
      #   @return [String, nil] fabrication number
      # @!attribute [r] fab_index
      #   @return [String, nil]
      # @!attribute [r] tech_type
      #   @return [String, nil] model name
      # @!attribute [r] mat_number
      #   @return [String, nil] material number
      # @!attribute [r] sw_ids
      #   @return [Array<Integer>, nil] software ids
      DeviceIdentificationLabel = Data.define(:version, :fab_number, :fab_index, :tech_type, :mat_number,
                                              :sw_ids) do
        include Value

        optional(*members)
        keys sw_ids: 'SWIDs'
      end

      # Label of an appliance's Wi-Fi module in its +Ident+ (Miele app class +XkmIdentificationLabelDto+).
      #
      # @!attribute [r] version
      #   @return [String, nil]
      # @!attribute [r] fab_number
      #   @return [String, nil] fabrication number
      # @!attribute [r] fab_index
      #   @return [String, nil]
      # @!attribute [r] tech_type
      #   @return [String, nil] module type, such as +EK057+
      # @!attribute [r] mat_number
      #   @return [String, nil] material number
      # @!attribute [r] sw_ids
      #   @return [Array<Integer>, nil] software ids
      # @!attribute [r] release_version
      #   @return [String, nil] software version of the module
      XkmIdentificationLabel = Data.define(:version, :fab_number, :fab_index, :tech_type, :mat_number, :sw_ids,
                                           :release_version) do
        include Value

        optional(*members)
        keys sw_ids: 'SWIDs'
      end

      # What an appliance is, from its +Ident+ (Miele app class +DeviceIdentificationDto+).
      #
      # @!attribute [r] device_type
      #   @return [Integer, nil] named by {Catalog::DEVICE_TYPES}
      # @!attribute [r] sub_type
      #   @return [Integer, nil]
      # @!attribute [r] ceced_type
      #   @return [Integer, nil]
      # @!attribute [r] device_name
      #   @return [String, nil]
      # @!attribute [r] device_ident_label
      #   @return [DeviceIdentificationLabel, nil]
      # @!attribute [r] app_support
      #   @return [Integer, nil]
      # @!attribute [r] fct_support
      #   @return [Integer, nil]
      # @!attribute [r] xkm_support
      #   @return [Integer, nil]
      # @!attribute [r] protocol_version
      #   @return [Integer, nil] 2 on Dop1 appliances, 3 or 4 on DOP2 ones
      # @!attribute [r] xkm_ident_label
      #   @return [XkmIdentificationLabel, nil]
      DeviceIdentification = Data.define(:device_type, :sub_type, :ceced_type, :device_name, :device_ident_label,
                                         :app_support, :fct_support, :xkm_support, :protocol_version,
                                         :xkm_ident_label) do
        include Value

        optional(*members)
        keys ceced_type: 'CECEDType', xkm_support: 'XKMSupport', xkm_ident_label: 'XKMIdentLabel'
        nested device_ident_label: DeviceIdentificationLabel, xkm_ident_label: XkmIdentificationLabel
      end
    end
  end
end
