# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramType+ of an appliance's +State+, as the Miele 3rd Party API
      # specification enumerates it (m3rdapi.yaml, 2022) and the Miele app
      # (4.19.0) reads it on Dop1 appliances, adding 4 and 5.
      PROGRAM_TYPES = {
        0 => :normal_operation, 1 => :own_program, 2 => :automatic_program, 3 => :cleaning_care_program,
        4 => :customer_service_program, 5 => :helper_program
      }.freeze

      # +ProgramType+ on DOP2 appliances, which the Miele app numbers from 1: an
      # oven in fan heating reports 1.
      DOP2_PROGRAM_TYPES = {
        1 => :normal_operation, 2 => :own_program, 3 => :automatic_program, 4 => :cleaning_care_program,
        5 => :customer_service_program, 6 => :helper_program
      }.freeze

      # +ProtocolVersion+ of DOP2 appliances, over M-Bus (3) or HDR (4).
      DOP2_PROTOCOL_VERSIONS = [3, 4].freeze

      # +ProtocolVersion+ of Dop1 appliances.
      DOP1_PROTOCOL_VERSION = 2
    end
  end
end
