# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # What the app's hood module writes only to a Dop1 hood (protocol 2), each section built from nothing as the
      # app builds it. {Readings} tells which features the hood supports, which the app shows alone.
      module Dop1Commands
        AMBIENT_MODES = { ambient: 1, cooking: 2 }.freeze
        DEHUMIDIFICATION_SETTINGS = { off: 0, controlled: 1, regulated: 2 }.freeze
        # The app's picker never offers controlled.
        DEHUMIDIFICATION_OFFERED = %i[off regulated].freeze
        FRAGRANCE_ACTIONS = { start: 0x34, stop: 0x35, miele_program: 0x35 }.freeze
        SILENCE_KEPT = %i[zeitraum_nr minuten_start stunden_start minuten_ende stunden_ende trocknungsdauer].freeze
        private_constant :AMBIENT_MODES, :DEHUMIDIFICATION_SETTINGS, :DEHUMIDIFICATION_OFFERED, :FRAGRANCE_ACTIONS,
                         :SILENCE_KEPT

        # @param mode [Symbol] +:ambient+, or +:cooking+ for the colours while cooking
        # @param rgb [Array(Integer, Integer, Integer)] red, green and blue
        # @param brightness [Integer]
        # @param colour_temperature [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, which has no Dop1 object to write
        # @raise [ArgumentError] for another mode, or a value out of 16 bits
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        # @api public
        def configure_ambient_light(mode:, rgb:, brightness:, colour_temperature:)
          selection = AMBIENT_MODES.fetch(mode) { raise ArgumentError, "no ambient light mode #{mode.inspect}" }
          require_dop1!
          red, green, blue = rgb
          write_section(Objects::Hood::ConfigAmbientLightW, struktur_version: 1, auswahl_da_betriebszustand: selection,
                                                            rot_dimmwert: red, gruen_dimmwert: green,
                                                            blau_dimmwert: blue, ww_dimmwert: brightness,
                                                            kw_dimmwert: colour_temperature)
        end

        # @param mode [Symbol] +:off+, +:controlled+ or +:regulated+, which PF 40025 takes as 0, 1 and 2
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, which has no Dop1 object to write
        # @raise [ArgumentError] for another mode
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        # @api public
        def dehumidification=(mode)
          value = DEHUMIDIFICATION_SETTINGS.fetch(mode) { raise ArgumentError, "no dehumidification #{mode.inspect}" }
          require_dop1!
          write_setting(40_025, value)
        end

        # @return [Array<Symbol>] the dehumidification modes the app's picker offers
        # @api public
        def dehumidification_modes = DEHUMIDIFICATION_OFFERED

        # The write carries the whole drying slot: the app copies it from what 8E0A reads.
        #
        # @param silent [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, which has no Dop1 object to write
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        # @api public
        def dehumidification_silent=(silent)
          require_dop1!
          slot = read_drying_slot
          write_section(Objects::Hood::ServiceDataExtEntfeuchtungSchreiben,
                        struktur_version: 1, betriebsart: slot.betriebsart == 2 ? 2 : 1,
                        geblaese_parameter: silent ? 1 : 0, **slot.to_h.slice(*SILENCE_KEPT))
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, which has no Dop1 object to write
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        # @api public
        def grease_melting=(on)
          require_dop1!
          write_section(Objects::Hood::FanHeaterW, struktur_version: 1, kommando: on ? 1 : 0)
        end

        # @param minutes [Integer] from now
        # @return [void]
        # @raise [ActionUnavailableError] on another protocol, which has no Dop1 object to write
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        # @api public
        def grease_melting_at(minutes)
          require_dop1!
          write_section(Objects::Hood::FanHeaterStartTimeW, struktur_version: 1, startzeit: minutes)
        end

        private

        # @param on [Boolean]
        # @return [void]
        def dop1_ambient_light(on)
          dimmer = on ? 1000 : 0
          values = { struktur_version: 1, lichtquelle: 2, da_beleuchtung_command: on ? 2 : 1,
                     a_ww_dimmwert_kf_helligkeit: dimmer, a_kw_dimmwert_kf_farb_temp: dimmer }
          write_section(Objects::Hood::SetLightW, **values)
        end

        # The app sends the stop request before PF 40026 for the Miele program too, and drops its Ack
        # (StopAnyProgramAsync, StartMieleProgramTodayAsync).
        #
        # @param action [Symbol] +:start+, +:stop+ or +:miele_program+
        # @return [void]
        def dop1_fragrance(action)
          id = FRAGRANCE_ACTIONS.fetch(action)
          request = section_request(Objects::Hood::ProcessAction, struktur_version: 1, action: id)
          return write_dop1(request) if action == :start

          dop1(request)
          write_setting(40_026, action == :miele_program ? 1 : 0)
        end

        # @return [void]
        # @raise [ActionUnavailableError] on another protocol
        def require_dop1! = require!(protocol_version == 2, 'only a Dop1 hood has this Dop1 object to write')

        # @param object [Class] a generated Dop1 object with one write section
        # @param values [Hash{Symbol=>Integer}] its members; the others stay 0
        # @return [void]
        # @raise [NotAcceptedError] when the hood answers an Ack other than 1
        def write_section(object, **values) = write_dop1(section_request(object, **values))

        # @param object [Class] a generated Dop1 object with one write section
        # @param values [Hash{Symbol=>Integer}] its members; the others stay 0
        # @return [String]
        def section_request(object, **values)
          section = object.const_get(object.constants.grep(/WriteSection\z/).first)
          bytes = section.from("\0" * section::LENGTH).with(**values).to_bytes
          Dop1.request(object_id: object::ID, type: Dop1::WRITE, section: bytes)
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
