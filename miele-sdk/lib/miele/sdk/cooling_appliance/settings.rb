# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The settings and lights of the app's refrigeration module; the predicates tell where the app shows a control
      # for them, and the choices what its pickers offer.
      module Settings
        HUMIDITY = { low: 1, medium: 2, high: 3 }.freeze
        private_constant :HUMIDITY

        # @param on [Boolean]
        # @return [void]
        # @api public
        def ice_maker=(on)
          put('Cooling', 'IceMaker', Value: on ? 1 : 2)
        end

        # @return [Boolean] whether the app shows the ice maker's switch: neither at Status 1 nor 255, on an
        #   appliance with an ice maker whose +IceMaker+ is 1, 2 or 3
        # @api public
        def ice_maker_offered?
          settings_listed?(state) && ice_maker? && [1, 2, 3].include?(cooling.dig('IceMaker', 'Value'))
        end

        # @param on [Boolean]
        # @return [void]
        # @api public
        def light=(on)
          if state_light?
            put('State', 'Light', Light: on ? 1 : 2)
          else
            put('Cooling', 'AmbientLightState', **switch(on))
          end
        end

        # @return [Boolean] whether the app switches the light: on a wine unit it lights, but a Rioja, where its
        #   light section or dashboard quick action {Screen#light_shown? shows}
        # @api public
        def light_offered? = wine? && !rioja? && light_shown?

        # @param value [Integer] the mode's number on a BSH wine unit, from 1 in its picker's order; the light's
        #   level on a Liebherr one
        # @return [void]
        # @raise [ActionUnavailableError] on a protocol but 200 and 203, which has no ambient light setting
        # @api public
        def ambient_light_mode=(value)
          require!([200, 203].include?(protocol_version), 'only protocols 200 and 203 have an ambient light setting')
          put('Cooling', ambient_light_key, Value: value)
        end

        # @return [Boolean] whether the app sets the ambient light: on a BSH wine unit, or a protocol 203 one
        #   neither KWTUS nor Rioja, with the light on and its setting listed, while its light section shows
        # @api public
        def ambient_light_offered?
          bsh = protocol_version == 200
          wine? && !rioja? && (bsh || (protocol_version == 203 && !kwtus?)) &&
            ambient_light_shown?(state, ambient_light_key)
        end

        # @return [Array<Integer>] the numbers the app's ambient light picker or seven-option slider offers
        # @api public
        def ambient_light_choices = ambient_light_numbers(ambient_light_key)

        # @param on [Boolean]
        # @return [void]
        # @api public
        def presentation_light=(on)
          put('Cooling', 'PresentationLight', Value: on ? 1 : 2)
        end

        # @return [Boolean] whether the app switches the presentation light: on a KWTUS or Rioja wine unit with
        #   one, where its presenter light section or dashboard quick action shows it
        # @api public
        def presentation_light_offered?
          return false unless presentation_light?

          state = self.state
          presenter_light_shown?(state) || presenter_quick_action?(state)
        end

        # The app's seven-option slider sends its index plus 1.
        #
        # @param zone [Zone] one of {#zones}
        # @param value [Integer] 0 switches the zone's light off, 1 to 7 sets its level
        # @return [void]
        # @api public
        def set_presentation_light_intensity(zone, value)
          put('Cooling', "#{zone.rank}/PresentationLightIntensity", Value: value)
        end

        # @return [Boolean] whether the app sets a zone's intensity: on a KWTUS or Rioja wine unit with a
        #   presentation light, while its presenter light section shows
        # @api public
        def presentation_light_intensity_offered? = presentation_light? && presenter_light_shown?(state)

        # @return [Array<Integer>] what the app offers: 0, and its slider's seven options
        # @api public
        def presentation_light_intensity_choices = (0..7).to_a

        # @param level [Symbol] +:low+, +:medium+ or +:high+
        # @return [void]
        # @raise [KeyError] for another level
        # @api public
        def humidity=(level)
          put('Cooling', 'HumidityControl', Value: HUMIDITY.fetch(level))
        end

        # @return [Boolean] whether the app shows its humidity control: on a KWTUS or Rioja wine unit, as
        #   HumidityControlRule
        # @api public
        def humidity_offered? = (rioja? || kwtus?) && humidity_control_shown?(state)

        # @return [Array<Symbol>] the levels the app offers: those on +HumidityControl+'s +Min+ to +Max+ by +Step+
        # @api public
        def humidity_choices
          offered = picker(cooling['HumidityControl'])
          HUMIDITY.filter_map { |level, value| level if offered.include?(value) }
        end

        # @param value [Integer]
        # @return [void]
        # @api public
        def perfect_fresh=(value)
          put('Cooling', 'PerfectFresh', Value: value)
        end

        # The app shows PerfectFresh for a +Step+ above 0 compared unsigned, so for any but 0.
        #
        # @return [Boolean] whether the app shows it: neither at Status 1 nor 255, not on protocol 201, where it
        #   reads none, and with a +Step+
        # @api public
        def perfect_fresh_offered?
          settings_listed?(state) && protocol_version != 201 && !cooling.dig('PerfectFresh', 'Step').to_i.zero?
        end

        # @return [Array<Integer>] what the app's picker offers: +PerfectFresh+'s +Min+ to +Max+ by +Step+
        # @api public
        def perfect_fresh_choices = picker(cooling['PerfectFresh'])

        # @param value [Integer]
        # @return [void]
        # @api public
        def humidifier=(value)
          put('Cooling', 'Humidifier', Value: value)
        end

        # @return [Boolean] whether the app shows the humidifier's cell: neither at Status 1 nor 255, with a
        #   +Humidifier+ whose +Value+ is not -1
        # @api public
        def humidifier_offered? = setting_shown?('Humidifier')

        # @return [Array<Integer>] what the app's picker offers: +Humidifier+'s +Min+ to +Max+ by +Step+
        # @api public
        def humidifier_choices = picker(cooling['Humidifier'])

        # @param seconds [Integer]
        # @return [void]
        # @api public
        def door_alarm_delay=(seconds)
          put('Cooling', 'DoorAlarmTime', Value: seconds)
        end

        # @return [Boolean] whether the app shows the door alarm delay's cell: neither at Status 1 nor 255, with a
        #   +DoorAlarmTime+ whose +Value+ is not -1
        # @api public
        def door_alarm_delay_offered? = setting_shown?('DoorAlarmTime')

        # @return [Array<Integer>] what the app's picker offers: +DoorAlarmTime+'s +Min+ to +Max+ by +Step+, in
        #   seconds
        # @api public
        def door_alarm_delay_choices = picker(cooling['DoorAlarmTime'])

        private

        # @return [String] +AmbientLightMode+ on a BSH appliance (protocol 200), +Light+ otherwise
        def ambient_light_key = protocol_version == 200 ? 'AmbientLightMode' : 'Light'

        # @param key [String] a +Cooling+ setting
        # @return [Boolean] listed, and at a +Value+ but -1
        def setting_shown?(key)
          setting = cooling[key]
          settings_listed?(state) && !setting.nil? && setting['Value'] != -1
        end
      end
    end
  end
end
