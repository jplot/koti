# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # What the app's hood module writes to a Dop1 hood (protocol 2), each section built alone as the app builds
      # it. A feature the hood does not support is refused, as the app hides it.
      module Dop1Commands
        AMBIENT_MODES = { ambient: 1, cooking: 2 }.freeze
        DEHUMIDIFICATION_SETTINGS = { off: 0, regulated: 2 }.freeze
        FRAGRANCE_ACTIONS = { start: 0x34, stop: 0x35, miele_program: 0x35 }.freeze
        SILENCE_KEPT = %i[zeitraum_nr minuten_start stunden_start minuten_ende stunden_ende trocknungsdauer].freeze
        private_constant :AMBIENT_MODES, :DEHUMIDIFICATION_SETTINGS, :FRAGRANCE_ACTIONS, :SILENCE_KEPT

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no ambient light
        # @api public
        def ambient_light=(on)
          require_ambient_light!
          dimmer = on ? 1000 : 0
          values = { struktur_version: 1, lichtquelle: 2, da_beleuchtung_command: on ? 2 : 1,
                     a_ww_dimmwert_kf_helligkeit: dimmer, a_kw_dimmwert_kf_farb_temp: dimmer }
          write_section(Objects::Hood::SetLightW, **values)
        end

        # @param mode [Symbol] +:ambient+, or +:cooking+ for the colours while cooking
        # @param rgb [Array(Integer, Integer, Integer)] red, green and blue
        # @param brightness [Integer]
        # @param colour_temperature [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no ambient light
        # @raise [ArgumentError] for another mode, or a value out of 16 bits
        # @api public
        def configure_ambient_light(mode:, rgb:, brightness:, colour_temperature:)
          selection = AMBIENT_MODES.fetch(mode) { raise ArgumentError, "no ambient light mode #{mode.inspect}" }
          require_ambient_light!
          red, green, blue = rgb
          write_section(Objects::Hood::ConfigAmbientLightW, struktur_version: 1, auswahl_da_betriebszustand: selection,
                                                            rot_dimmwert: red, gruen_dimmwert: green,
                                                            blau_dimmwert: blue, ww_dimmwert: brightness,
                                                            kw_dimmwert: colour_temperature)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol
        # @api public
        def ambient_light_while_cooking=(on)
          require_dop1!
          write_setting(40_029, on ? 1 : 0)
        end

        # @return [void]
        # @raise [ActionUnavailableError] on another protocol
        # @api public
        def reset_grease_filter
          require_dop1!
          write_setting(40_012, 1)
        end

        # @return [void]
        # @raise [ActionUnavailableError] on another protocol
        # @api public
        def reset_charcoal_filter
          require_dop1!
          write_setting(40_013, 1)
        end

        # @param mode [Symbol] +:off+ or +:regulated+: the app never writes +:controlled+
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood does not dehumidify
        # @raise [ArgumentError] for another mode
        # @api public
        def dehumidification=(mode)
          value = DEHUMIDIFICATION_SETTINGS.fetch(mode) { raise ArgumentError, "no dehumidification #{mode.inspect}" }
          require_feature!(dehumidification&.supported, 'the hood does not dehumidify')
          write_setting(40_025, value)
        end

        # The write carries the whole drying slot: the app copies it from what 8E0A reads.
        #
        # @param silent [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood does not dehumidify
        # @api public
        def dehumidification_silent=(silent)
          require_feature!(dehumidification&.supported, 'the hood does not dehumidify')
          slot = read_drying_slot
          write_section(Objects::Hood::ServiceDataExtEntfeuchtungSchreiben,
                        struktur_version: 1, betriebsart: slot.betriebsart == 2 ? 2 : 1,
                        geblaese_parameter: silent ? 1 : 0, **slot.to_h.slice(*SILENCE_KEPT))
        end

        # The app sends the stop request before PF 40026 for the Miele program too.
        #
        # @param action [Symbol] +:start+ (20 minutes), +:stop+ or +:miele_program+
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no fragrance
        # @raise [ArgumentError] for another action
        # @api public
        def fragrance(action)
          code = FRAGRANCE_ACTIONS.fetch(action) { raise ArgumentError, "no fragrance action #{action.inspect}" }
          require_dop1!
          require!(setting(40_028).to_i[7] == 1, 'the hood has no fragrance')
          write_section(Objects::Hood::ProcessAction, struktur_version: 1, action: code)
          write_setting(40_026, action == :miele_program ? 1 : 0) unless action == :start
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no grease melting
        # @api public
        def grease_melting=(on)
          require_feature!(grease_melting&.supported, 'the hood has no grease melting')
          write_section(Objects::Hood::FanHeaterW, struktur_version: 1, kommando: on ? 1 : 0)
        end

        # @param minutes [Integer] from now
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no grease melting
        # @api public
        def grease_melting_at(minutes)
          require_feature!(grease_melting&.supported, 'the hood has no grease melting')
          write_section(Objects::Hood::FanHeaterStartTimeW, struktur_version: 1, startzeit: minutes)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, or when the hood has no auto refresh
        # @api public
        def auto_refresh=(on)
          require_feature!(auto_refresh_supported?, 'the hood has no auto refresh')
          write_setting(40_023, on ? 1 : 0)
        end

        # A Dop1 or Opcode hood wakes when its State is written back, the light as it is; DOP2 takes
        # +DeviceAction+ 2 (DefaultWakeUpAction).
        #
        # @return [void]
        # @api public
        def wake
          return super if [3, 4].include?(protocol_version)

          state = self.state
          command(Schema::DeviceState.new(light: state.raw['Light'])) if state.status == :off
        end

        private

        # @return [void]
        # @raise [ActionUnavailableError] on another protocol
        def require_dop1! = require!(protocol_version == 2, 'only a Dop1 hood takes this, as in the app')

        # @param supported [Boolean, nil]
        # @param reason [String]
        # @return [void]
        # @raise [ActionUnavailableError]
        def require_feature!(supported, reason)
          require_dop1!
          require!(supported, reason)
        end

        # @return [void]
        # @raise [ActionUnavailableError]
        def require_ambient_light! = require_feature!(lights&.ambient&.exists, 'the hood has no ambient light')

        # @param object [Class] a generated Dop1 object with one write section
        # @param values [Hash{Symbol=>Integer}] its members; the others stay 0
        # @return [void]
        def write_section(object, **values)
          section = object.const_get(object.constants.grep(/WriteSection\z/).first)
          bytes = section.from("\0" * section::LENGTH).with(**values).to_bytes
          tolerating_no_op { dop1(Dop1.request(object_id: object::ID, type: Dop1::WRITE, section: bytes)) }
        end

        # @return [Data] the first drying slot, as 8E0A answers it
        def read_drying_slot
          object = Objects::Hood::ServiceDataExtEntfeuchtungLesen
          query = object::ServiceDataExtEntfeuchtungWriteSection
          bytes = query.from("\0" * query::LENGTH).with(struktur_version: 1, betriebsart: 2, zeitraum_nr: 1).to_bytes
          answer = JSON.parse(dop1(Dop1.request(object_id: object::ID, type: Dop1::READ, section: bytes)))
          object::ServiceDataExtEntfeuchtungSection.from([answer.fetch('Response')[8..]].pack('H*'), endian: :msb)
        end
      end
    end
  end
end
