# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The rules by which the app's refrigeration screens show their controls; the SDK refuses what they hide.
      module Screen
        private

        # @param state [State]
        # @return [void]
        # @raise [ActionUnavailableError] while the app hides the zones
        def require_zones_shown!(state = self.state)
          require!(zones_shown?(state), 'the app shows no zone now')
        end

        # @param state [State]
        # @return [Boolean] as GetVisibleElementsFields decides
        def zones_shown?(state)
          case app_state(state)
          when :off then false
          when :on then !holiday_or_sabbath?(state) || failure_alarm?
          when :failure then holiday_or_sabbath?(state) || failure_alarm?
          else true
          end
        end

        # ApplianceStateRule: a door signal turns on, running and super freezing into DoorOpen or DoorAlarm, but only
        # a door alarm turns a failure into DoorAlarm.
        #
        # @param state [State]
        # @return [Symbol] +:off+, +:on+ (on, running or super freezing), +:failure+, or +:other+
        def app_state(state)
          status = state.raw['Status']
          door = door_signal(state)
          return :off if shown_off?(state)
          return :on if [2, 5, 13].include?(status) && door.zero?

          status == 8 && door != 2 ? :failure : :other
        end

        # @param state [State]
        # @return [Boolean] Status 1, 10 or 255, which the app shows as off or not connected
        def shown_off?(state) = [1, 10, 255].include?(state.raw['Status'])

        # @param state [State]
        # @return [Integer] DoorStateSource's signal: 0 none, 1 door open, 2 door alarm
        def door_signal(state)
          return 0 unless state.raw['SignalDoor'] == true && !state.raw['SignalFailure'].nil?

          state.raw['SignalFailure'] ? 2 : 1
        end

        # @param state [State]
        # @return [Boolean]
        def holiday_or_sabbath?(state) = modes(state).values_at(:holiday, :sabbath).any? { it&.on }

        # @return [Boolean] the ice maker's alarm or a zone's, which the app reads on the Cooling API alone
        def failure_alarm?
          return false unless cooling_api?

          listed = cooling
          listed.dig('IceMaker', 'Value') == 3 || zone_alarm?(listed)
        end

        # UpdateTemperatureAlarms counts a temperature alarm only in a freezer or a wine unit zone.
        #
        # @param listed [Hash{String=>Object}] +Cooling+
        # @return [Boolean] a power failure or temperature alarm in a zone the app keeps
        def zone_alarm?(listed)
          zones = (1..listed['ZoneCounter'].to_i).map { device("Cooling/#{it}") }
          zones.each_with_index.any? do |zone, index|
            alarm = zone.dig('PowerFailAlarm', 'Value') == 3 ||
                    (zone.dig('TempAlarm', 'Value') == 3 && freezer_or_wine_unit_zone?(zones, index))
            alarm && listed_zone?(zone)
          end
        end

        # GetZoneSubType makes a wine zone a wine unit zone but past the third, or the third before a wine zone.
        #
        # @param zones [Array<Hash{String=>Object}>] each +Cooling/{n}+
        # @param index [Integer]
        # @return [Boolean]
        def freezer_or_wine_unit_zone?(zones, index)
          return true if zones[index].dig('ZoneState', 'Type') == 20

          wine_zone?(zones[index]) && (index < 2 || (index == 2 && !wine_zone?(zones[3])))
        end

        # @param zone [Hash{String=>Object}, nil] +Cooling/{n}+
        # @return [Boolean] a wine cabinet, wine conditioning or wine storage conditioning zone
        def wine_zone?(zone) = (32..34).cover?(zone&.dig('ZoneState', 'Type'))
      end
    end
  end
end
