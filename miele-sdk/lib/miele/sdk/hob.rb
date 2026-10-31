# frozen_string_literal: true

module Miele
  module Sdk
    # A hob, which the Miele app's hob module handles (device types 14, 27 and 28). The app reads it only: its
    # actions are Cook Assist commands through the Miele cloud.
    class Hob < Appliance
      include Zones

      INTERNAL_STATES = { 1 => :off, 2 => :standby, 3 => :programmed, 5 => :running, 8 => :failure, 10 => :settings,
                          11 => :support, 12 => :service, 145 => :locked, 146 => :stop_and_go, 147 => :cleaning,
                          149 => :user_confirm_required, 150 => :user_confirmed, 151 => :user_confirm_failed,
                          152 => :user_confirm_timeout }.freeze
      TEMP_CONTROL_LEVELS = { 4 => :simmer, 7 => :one, 8 => :two, 9 => :three, 11 => :custom }.freeze
      FAN_LEVELS = { 0 => 0, 1 => 1, 2 => 2, 3 => 3, 4 => :booster, 5 => 4, 6 => 5, 7 => 6, 8 => 7, 9 => 8,
                     10 => 9 }.freeze
      DOP2_MAIN_STATES = { on: :stand_by, off: :off, running: :running, failure: :failure, locked: :locked,
                           service: :service }.freeze
      # The app tells a hob's kind by the length of its ExtendedState, 22 zeros ahead: only these have a fan.
      FAN_LENGTHS = [88, 128, 159].freeze
      ZONE_CONTROL_LENGTHS = [128, 159].freeze
      NO_FLEX_ZONE_LENGTH = 159
      private_constant :INTERNAL_STATES, :TEMP_CONTROL_LEVELS, :FAN_LEVELS, :DOP2_MAIN_STATES, :FAN_LENGTHS,
                       :ZONE_CONTROL_LENGTHS, :NO_FLEX_ZONE_LENGTH

      # @return [Symbol, Integer, nil] +:stand_by+, +:running+, +:failure+, +:service+, +:off+, +:locked+ or
      #   +:stop_and_go+; +:off+ when the hob serves no ExtendedState
      # @api public
      def main_state
        return DOP2_MAIN_STATES[object(Objects::Hob::GlobalDsDeviceState).main_state] if dop2?

        state.extended_state&.geraetespezifische_informationen&.hauptzustand_des_kochfeldes || :off
      end

      # @return [Symbol] the app's InternalApplianceState: +:stop_and_go+, +:locked+, +:cleaning+, … or +:unknown+
      # @api public
      def internal_state = dop2? ? :unknown : INTERNAL_STATES.fetch(state.raw['InternalState'], :unknown)

      # @return [Array<Zone>] the zones the hob declares, by number; a DOP2 hob's first two, as the app shows them
      # @api public
      def zones
        return dop2_zones if dop2?

        state = self.state
        return [] unless state.extended_state

        zones = numbered_zones(state).sort_by(&:number)
        padded_length(state) == NO_FLEX_ZONE_LENGTH ? zones : flexed(zones)
      end

      # @return [Integer, nil] seconds left on the minute minder
      # @api public
      def minute_minder
        return if dop2?

        general = state.extended_state&.geraetespezifische_informationen
        return unless general

        seconds = (general.kurzzeit_stunden * 3600) + (general.kurzzeit_minuten * 60) + general.kurzzeit_sekunden
        seconds unless seconds.zero?
      end

      # @return [Boolean, nil] whether the hob doubles its levels into half steps
      # @api public
      def power_doubling? = dop2? || general_flag(:leistungsstufenverdopplung)

      # @return [Boolean, nil]
      # @api public
      def stop_and_go? = (general_flag(:stop_zustand) unless dop2?)

      # @return [TempControl, nil] for the first zone that has it, nil on an Opcode or DOP2 hob, as in the app
      # @api public
      def temp_control
        return unless protocol_version == 2

        state = self.state
        zone = state.extended_state && numbered_zones(state).find(&:temp_control)
        temp_control_of(state, zone.number) if zone && (1..6).cover?(zone.number)
      end

      # @return [Fan, nil] nil for a hob without one (0xFF or another length), or an Opcode or DOP2 hob, as in the app
      # @api public
      def fan
        return unless protocol_version == 2

        state = self.state
        return unless state.extended_state && FAN_LENGTHS.include?(padded_length(state))

        fan = state.extended_state.luefter
        raw = Objects::Hob::LuefterstufeEnum0002.to_i(fan.luefterstufe)
        Fan.new(FAN_LEVELS[raw], run_on(fan)) unless raw == 0xFF
      end

      private

      # @return [Boolean]
      def dop2? = protocol_version == 4

      # @param state [State]
      # @return [Array<Zone>] the existing zones, numbered as the app numbers them
      def numbered_zones(state)
        general = state.extended_state.geraetespezifische_informationen
        zones = existing_zones(general, general.kochfeldinformationen.anzahl_der_kochstellen)
        return zones unless protocol_version == 2 && ZONE_CONTROL_LENGTHS.include?(padded_length(state))

        renumbered(zones, state.extended_state)
      end

      # @param state [State]
      # @return [Integer]
      def padded_length(state) = 22 + (state.raw['ExtendedState'].to_s.size / 2)

      # @param name [Symbol] a bit of +Allg_Kochfeldinformationen+
      # @return [Boolean, nil]
      def general_flag(name)
        general = state.extended_state&.geraetespezifische_informationen
        general && general.allg_kochfeldinformationen.public_send(name) == :aktiviert
      end

      # @param state [State]
      # @param number [Integer] the zone's
      # @return [TempControl]
      def temp_control_of(state, number)
        setting = state.extended_state.temp_control.public_send(:"kochstelle_#{number}")
        level = Objects::Hob::BenutzereinstellungTempcontrolEnum.to_i(setting.benutzereinstellung)
        TempControl.new(number, TEMP_CONTROL_LEVELS.fetch(level, :none), setting.zieltemperatur == :erreicht,
                        degrees(state.raw['TargetTemperature']), degrees(state.raw['Temperature']))
      end

      # MapTempControl: whole degrees, truncated, and 0 where the hob reports none.
      #
      # @param values [Array<Integer>, nil] hundredths of a degree
      # @return [Integer]
      def degrees(values) = Array(values).first.to_i.then { it.positive? ? it / 100 : 0 }

      # AddFanData builds TimeSpan(0, minutes, the byte named hours): that byte counts seconds.
      #
      # @param fan [Data] +Luefter+
      # @return [Integer] seconds
      def run_on(fan) = (fan.luefter_nachlaufzeit_minuten * 60) + fan.luefter_nachlaufzeit_stunden

      # FromDop2DeviceStateMapper shows two zones, with half steps.
      #
      # @return [Array<Zone>]
      def dop2_zones
        extended = object(Objects::Hob::GlobalDsDeviceState).hob_extended_state
        [1, 2].map do |number|
          raw = extended&.public_send(:"power_level_zone#{number}").to_i
          duration = extended&.public_send(:"duration_zone#{number}").to_i
          Zone.new(number, level(raw, true), HEATS[raw], 0, timer(duration), false, false, false, false)
        end
      end
    end
  end
end
