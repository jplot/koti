# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +ProgramType+ of an appliance's +State+, as the Miele 3rd Party API
      # specification enumerates it (m3rdapi.yaml, 2022).
      PROGRAM_TYPES = {
        0 => :normal_operation, 1 => :own_program, 2 => :automatic_program, 3 => :cleaning_care_program
      }.freeze
    end
  end
end
