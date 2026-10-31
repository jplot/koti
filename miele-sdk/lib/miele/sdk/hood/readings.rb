# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # The fan's run-on.
      #
      # @!attribute [r] setting
      #   @return [Integer] 0, 5 or 15 minutes, as the app rounds what is left and what has run
      # @!attribute [r] minutes_left
      #   @return [Integer]
      RunOn = Data.define(:setting, :minutes_left)

      # A hood light.
      #
      # @!attribute [r] exists
      #   @return [Boolean]
      # @!attribute [r] dimmable
      #   @return [Boolean]
      # @!attribute [r] rgb
      #   @return [Boolean]
      # @!attribute [r] temperature_settable
      #   @return [Boolean] whether its colour temperature can be set
      # @!attribute [r] dimmer
      #   @return [Integer] 0 to 65535, as the hood reports it
      # @!attribute [r] temperature
      #   @return [Integer] its colour temperature, as the hood reports it
      Light = Data.define(:exists, :dimmable, :rgb, :temperature_settable, :dimmer, :temperature)

      # The main and ambient lights.
      #
      # @!attribute [r] main
      #   @return [Light]
      # @!attribute [r] ambient
      #   @return [Light]
      Lights = Data.define(:main, :ambient)

      # A grease or charcoal filter.
      #
      # @!attribute [r] threshold
      #   @return [Integer] hours
      # @!attribute [r] hours
      #   @return [Integer] hours run since the last reset
      # @!attribute [r] reached
      #   @return [Boolean]
      Filter = Data.define(:threshold, :hours, :reached)

      # Dehumidification.
      #
      # @!attribute [r] supported
      #   @return [Boolean]
      # @!attribute [r] mode
      #   @return [Symbol] +:off+, +:controlled+, +:regulated+ or +:unknown+
      # @!attribute [r] state
      #   @return [Symbol] +:deactivated+, +:drying+, +:pending+ or +:unknown+
      Dehumidification = Data.define(:supported, :mode, :state)

      # The blower cleaning, which the app calls grease melting.
      #
      # @!attribute [r] supported
      #   @return [Boolean]
      # @!attribute [r] minutes_left
      #   @return [Integer]
      # @!attribute [r] threshold
      #   @return [Integer] hours between two meltings
      # @!attribute [r] hours
      #   @return [Integer] hours since the last one
      GreaseMelting = Data.define(:supported, :minutes_left, :threshold, :hours)

      # ColorFlow, the light colours cycling.
      #
      # @!attribute [r] active
      #   @return [Boolean]
      # @!attribute [r] interval
      #   @return [Integer] seconds
      ColorFlow = Data.define(:active, :interval)

      # Seconds between two colours (ColorFlowInterval).
      COLOR_FLOW_INTERVALS = [5, 10, 20].freeze
      private_constant :COLOR_FLOW_INTERVALS

      # Con@ctivity Plus, which makes the hood follow hobs.
      #
      # @!attribute [r] available
      #   @return [Boolean, nil]
      # @!attribute [r] activated
      #   @return [Boolean, nil]
      # @!attribute [r] available_sources
      #   @return [Array<String>, nil] the fabrication numbers of the hobs it can follow
      # @!attribute [r] sources
      #   @return [Array<String>, nil] those it follows
      ConnectivityPlus = Data.define(:available, :activated, :available_sources, :sources)

      # What the app's hood module reads from ExtendedState (DopDeviceStateMapper). An Opcode hood (protocol 1)
      # has a shorter ExtendedState and gives its fan and light in State (OpCodeDeviceStateMapper).
      module Readings
        DEHUMIDIFICATION_MODES = { 0 => :off, 1 => :controlled, 2 => :regulated }.freeze
        DEHUMIDIFICATION_STATES = { 0 => :deactivated, 1 => :drying, 3 => :pending }.freeze
        NO_AUTO_REFRESH = /DA35|DA36|DAD|DAS/i
        private_constant :DEHUMIDIFICATION_MODES, :DEHUMIDIFICATION_STATES, :NO_AUTO_REFRESH

        # @return [Integer, nil] 0 to 3, 4 for boost, 5 for interval, 8 while the hood adjusts its pressure; nil
        #   when the hood serves no ExtendedState
        # @api public
        def fan_level
          return state.ventilation_step.to_i if opcode?

          extended&.luefter_1&.luefterstufe_luefter_1
        end

        # @return [Boolean, nil] false while the hood's screen is pushed in
        # @api public
        def fan_settable? = extended&.then { it.hinweise1.haubenschirm == 1 }

        # @return [Boolean, nil]
        # @api public
        def booster_2_available? = extended&.then { !opcode? && second_functions(it)[7] == 1 }

        # @return [RunOn, nil]
        # @api public
        def run_on = extended&.then { opcode? ? opcode_run_on(it) : dop_run_on(it) }

        # @return [Lights, nil]
        # @api public
        def lights
          return opcode_lights if opcode?

          extended&.then { Lights.new(main: main_light_state(it), ambient: ambient_light_state(it)) }
        end

        # @return [Filter, nil]
        # @api public
        def grease_filter = filter(:fett, :fettfiltergrenze_ueberschritten)

        # @return [Filter, nil]
        # @api public
        def charcoal_filter = filter(:kohle, :kohlefiltergrenze_ueberschritten)

        # @return [Integer, nil]
        # @api public
        def height_position = dop_extended&.status_hoehenverstellung&.status_hoehenverstellung

        # @return [Dehumidification, nil]
        # @api public
        def dehumidification
          dop_extended&.then do |values|
            mode = values.betriebsart_entfeuchtung.betriebsart_entfeuchtung
            state = values.status_entfeuchtung.status_entfeuchtung
            Dehumidification.new(second_functions(values)[3] == 1, DEHUMIDIFICATION_MODES.fetch(mode, :unknown),
                                 DEHUMIDIFICATION_STATES.fetch(state, :unknown))
          end
        end

        # @return [GreaseMelting, nil]
        # @api public
        def grease_melting
          dop_extended&.then do |values|
            GreaseMelting.new(second_functions(values)[9] == 1,
                              values.restlaufzeit_geblaesereinigung.restlaufzeit_geblaesereinigung,
                              values.schwellwert_geblaesereinigung.schwellwert_geblaesereinigung,
                              values.betriebsstunden_geblaese.betriebsstunden_geblaese)
          end
        end

        # The app also leaves it out for the DA35, DA36, DAD and DAS models.
        #
        # @return [Boolean, nil]
        # @api public
        def auto_refresh_supported?
          dop_extended&.then { functions(it)[0] == 1 && !tech_type.to_s.match?(NO_AUTO_REFRESH) }
        end

        # @return [ConnectivityPlus, nil] nil when +services+ has none
        # @api public
        def connectivity_plus
          plus = services['ConnectivityPlus']
          return unless plus

          ConnectivityPlus.new(available: plus['available'], activated: plus['activated'],
                               available_sources: plus['availableSourceDeviceIds'], sources: plus['sourceDeviceIds'])
        end

        # A DOP2 hood answering 500 has none either, and an interval the app does not know reads 10
        # (ColorFlowDop2Source, ColorFlowIntervalMapper).
        #
        # @return [ColorFlow, nil] nil when the hood has none
        # @api public
        def color_flow
          return if opcode?

          served = device('ColorFlow')
          interval = served.fetch('intervalDurationSeconds')
          ColorFlow.new(served.fetch('active'), COLOR_FLOW_INTERVALS.include?(interval) ? interval : 10)
        rescue NotFoundError
          nil
        rescue ResponseError => e
          raise unless e.status == 500 && protocol_version != 2
        end

        private

        # @return [Boolean]
        def opcode? = protocol_version == 1

        # @return [Data, nil]
        def extended = state.extended_state

        # @return [Data, nil] nil for an Opcode hood, whose ExtendedState lacks these values
        def dop_extended = (extended unless opcode?)

        # @param values [Data]
        # @return [Integer] +Unterstuetzte_Funktionen+, the bits of what the hood supports
        def functions(values) = values.unterstuetzte_funktionen.unterstuetzte_funktionen

        # @param values [Data]
        # @return [Integer] +Unterstuetzte_Funktionen_2+
        def second_functions(values) = values.unterstuetzte_funktionen_2.unterstuetzte_funktionen_2

        # @param values [Data]
        # @return [RunOn] GetRunOnTimeSetting: what is left plus what has run, 0 once nothing is left
        def dop_run_on(values)
          left = values.rest_zeit_luefternachlauf_minuten.rest_zeit_luefternachlauf_minuten
          run = values.verstrichene_zeit_luefternachlauf_minuten.verstrichene_zeit_luefternachlauf_minuten
          RunOn.new(run_on_setting(left.zero? ? 0 : left + run), left)
        end

        # @param values [Data]
        # @return [RunOn] one byte for both
        def opcode_run_on(values)
          minutes = values.luefternachlauf.luefternachlauf
          RunOn.new(run_on_setting(minutes), minutes)
        end

        # @param minutes [Integer]
        # @return [Integer] MapRunOnTimeLevel: 0, then 5 up to 5 minutes, 15 above
        def run_on_setting(minutes)
          return 0 if minutes.zero?

          minutes <= 5 ? 5 : 15
        end

        # @param kind [Symbol] +:fett+ or +:kohle+
        # @param reached [Symbol] its +Hinweise1+ bit
        # @return [Filter, nil]
        def filter(kind, reached)
          extended&.then do |values|
            threshold = values.public_send(:"schwellwert_#{kind}").public_send(:"schwellwert_#{kind}filter")
            hours = values.public_send(:"#{kind}filter_betriebsstunden").public_send(:"#{kind}filter_betriebsstunden")
            Filter.new(threshold, hours, opcode? ? threshold - hours <= 0 : values.hinweise1.public_send(reached) == 1)
          end
        end

        # @param values [Data]
        # @return [Light]
        def main_light_state(values)
          bits = functions(values)
          Light.new(bits[1] == 1, bits[4] == 1, bits[7] == 1, bits[11] == 1, values.licht_1_dimm.licht_1,
                    values.licht_1_temperatur.licht_1_temperatur)
        end

        # @param values [Data]
        # @return [Light]
        def ambient_light_state(values)
          bits = functions(values)
          Light.new(bits[2] == 1 && ambient_panel?(bits), bits[5] == 1, bits[8] == 1, bits[12] == 1,
                    values.licht_2_dimm.licht_2, values.licht_2_temperatur.licht_2_temperatur)
        end

        # An ambient light exists with bit 8 on DOP2, with an RGB panel (setting 40028) on Dop.
        #
        # @param bits [Integer] +Unterstuetzte_Funktionen+
        # @return [Boolean]
        def ambient_panel?(bits) = protocol_version == 2 ? setting(40_028).to_i.allbits?(7) : bits[8] == 1

        # +Light+ 0 means the hood has none, 2 that it is off (OpCodeDeviceStateMapper).
        #
        # @return [Lights]
        def opcode_lights
          light = state.raw['Light']
          main = Light.new(light != 0, false, false, false, light == 2 ? 0 : 65_535, 0)
          Lights.new(main, Light.new(false, false, false, false, 0, 0))
        end
      end
    end
  end
end
