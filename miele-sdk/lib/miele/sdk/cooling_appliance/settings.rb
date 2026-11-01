# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The settings and lights of the app's refrigeration module, refused where the app shows no control for them.
      module Settings
        HUMIDITY = { low: 1, medium: 2, high: 3 }.freeze
        private_constant :HUMIDITY

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] at Status 1 or 255, or on an appliance without an ice maker, or whose
        #   +IceMaker+ is not 1, 2 or 3, where the app hides its switch
        # @api public
        def ice_maker=(on)
          require!(settings_listed?(state), 'the app shows no settings at Status 1 or 255')
          require!(ice_maker?, 'the appliance has no ice maker')
          require!([1, 2, 3].include?(cooling.dig('IceMaker', 'Value')), 'the appliance reports no ice maker state')
          put('Cooling', 'IceMaker', Value: on ? 1 : 2)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] but on a wine unit the app lights, where its light section or dashboard
        #   quick action shows
        # @api public
        def light=(on)
          require!(wine? && !rioja?, 'the app switches no light on this appliance')
          require!(light_shown?(state), 'the app shows no light switch now')
          if state_light?
            put('State', 'Light', Light: on ? 1 : 2)
          else
            put('Cooling', 'AmbientLightState', **switch(on))
          end
        end

        # @param value [Integer] the mode's number on a BSH wine unit, from 1 in its picker's order; the light's
        #   level on a Liebherr one, 1 to 7
        # @return [void]
        # @raise [ActionUnavailableError] but on a BSH wine unit, or a protocol 203 one neither KWTUS nor Rioja, with
        #   the light on and its setting listed, while the app shows its light section
        # @raise [ArgumentError] for a number or level the app's picker or slider does not offer
        # @api public
        def ambient_light_mode=(value)
          bsh = protocol_version == 200
          require!(wine? && !rioja? && (bsh || (protocol_version == 203 && !kwtus?)),
                   'the app sets no ambient light on this appliance')
          key = bsh ? 'AmbientLightMode' : 'Light'
          require!(ambient_light_shown?(state, key), 'the app shows no ambient light now')
          require_offered!(value, ambient_light_numbers(key))
          put('Cooling', key, Value: value)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] but on a KWTUS or Rioja wine unit with one, where the app's presenter light
        #   section or dashboard quick action shows it
        # @api public
        def presentation_light=(on)
          require!(presentation_light?, 'the appliance has no presentation light')
          state = self.state
          require!(presenter_light_shown?(state) || presenter_quick_action?(state),
                   'the app shows no presentation light now')
          put('Cooling', 'PresentationLight', Value: on ? 1 : 2)
        end

        # The app sends 0 for a zone switched off, else its seven-option slider's index plus 1.
        #
        # @param zone [Zone] one of {#zones}
        # @param value [Integer] 0 switches the zone's light off, 1 to 7 sets its level
        # @return [void]
        # @raise [ActionUnavailableError] but on a KWTUS or Rioja wine unit with a presentation light, while the
        #   app's presenter light section shows
        # @raise [ArgumentError] outside 0 to 7
        # @api public
        def set_presentation_light_intensity(zone, value)
          require!(presentation_light?, 'the appliance has no presentation light')
          require!(presenter_light_shown?(state), 'the app shows no presentation light now')
          require_offered!(value, (0..7).to_a)
          put('Cooling', "#{zone.rank}/PresentationLightIntensity", Value: value)
        end

        # @param level [Symbol] +:low+, +:medium+ or +:high+
        # @return [void]
        # @raise [ActionUnavailableError] but on a KWTUS or Rioja wine unit, while the app shows its humidity control
        # @raise [ArgumentError] for a level off +HumidityControl+'s +Min+ to +Max+ by +Step+, which the app offers
        # @api public
        def humidity=(level)
          require!(rioja? || kwtus?, 'the appliance has no humidity control')
          require!(humidity_control_shown?(state), 'the app shows no humidity control now')
          value = HUMIDITY.fetch(level)
          require_offered!(value, picker(cooling['HumidityControl']))
          put('Cooling', 'HumidityControl', Value: value)
        end

        # The app shows PerfectFresh for a +Step+ above 0 compared unsigned, so for any but 0.
        #
        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] at Status 1 or 255, on protocol 201, where the app reads none, or without a
        #   +Step+
        # @raise [ArgumentError] off +PerfectFresh+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def perfect_fresh=(value)
          require!(settings_listed?(state), 'the app shows no settings at Status 1 or 255')
          setting = cooling['PerfectFresh']
          require!(protocol_version != 201 && !setting.to_h['Step'].to_i.zero?, 'the app shows no PerfectFresh here')
          require_offered!(value, picker(setting))
          put('Cooling', 'PerfectFresh', Value: value)
        end

        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] at Status 1 or 255, without +Humidifier+ or at its +Value+ -1, where the app
        #   hides the cell
        # @raise [ArgumentError] off +Humidifier+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def humidifier=(value)
          require!(settings_listed?(state), 'the app shows no settings at Status 1 or 255')
          setting = cooling['Humidifier']
          require!(setting && setting['Value'] != -1, 'the app shows no humidifier')
          require_offered!(value, picker(setting))
          put('Cooling', 'Humidifier', Value: value)
        end

        # @param seconds [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] at Status 1 or 255, without +DoorAlarmTime+ or at its +Value+ -1, where the
        #   app hides the cell
        # @raise [ArgumentError] off +DoorAlarmTime+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def door_alarm_delay=(seconds)
          require!(settings_listed?(state), 'the app shows no settings at Status 1 or 255')
          setting = cooling['DoorAlarmTime']
          require!(setting && setting['Value'] != -1, 'the app shows no door alarm delay')
          require_offered!(seconds, picker(setting))
          put('Cooling', 'DoorAlarmTime', Value: seconds)
        end
      end
    end
  end
end
