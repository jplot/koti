# frozen_string_literal: true

module Miele
  module Sdk
    module Catalog
      # +Status+ of an appliance's +State+, as the Miele 3rd Party API
      # specification enumerates it (m3rdapi.yaml, 2022).
      STATUS = {
        1 => :off, 2 => :on, 3 => :programmed, 4 => :waiting_to_start, 5 => :running, 6 => :pause,
        7 => :end_programmed, 8 => :failure, 9 => :programme_interrupted, 10 => :idle, 11 => :rinse_hold,
        12 => :service, 13 => :superfreezing, 14 => :supercooling, 15 => :superheating,
        146 => :supercooling_superfreezing, 255 => :not_connected
      }.freeze
    end
  end
end
