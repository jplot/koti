# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The actions of the app's refrigeration module. The app checks nothing before them but the protocol and
      # the kind of appliance, and reads no +RemoteEnable+; the SDK refuses what the app offers no control for.
      module Commands
        # +ProcessAction+ on and off for an Opcode fridge and freezer zone; the app sends 0 for any other.
        SUPER_MODE_ACTIONS = { fridge: [6, 7], freezer: [4, 5] }.freeze
        HUMIDITY = { low: 1, medium: 2, high: 3 }.freeze
        private_constant :SUPER_MODE_ACTIONS, :HUMIDITY

        # An Opcode appliance takes its target through +Oc85+, as 16-bit two's complement of whole °C. As the app's
        # ChangeTargetTemperatureAsync, nothing goes out for the zone's current target.
        #
        # @param zone [Zone] one of {#zones}
        # @param degrees [Integer] whole degrees in {#temperature_unit}
        # @return [void]
        # @raise [ArgumentError] for a fraction of a degree, which the app never sends, or a value its picker does
        #   not offer
        # @raise [ActionUnavailableError] while the app hides the zones
        # @api public
        def set_target(zone, degrees)
          raise ArgumentError, 'the app sets whole degrees' unless degrees.is_a?(Integer)

          state = self.state
          require_zones_shown!(state)
          return unless new_target?(zone, degrees, state)
          return put('Cooling', "#{zone.number}/TargetTemp", Value: degrees * 100) unless opcode?

          request = "10000617000#{zone.number}00#{format('%04X', degrees & 0xFFFF)}"
          send_request(:post, "/Devices/#{fab}/Oc85/", body: JSON.generate(Request: request))
        end

        # On protocol 201 the app first sets the duration to 720, whatever that write answers, and waits 500 ms.
        #
        # @param zone [Zone] one of {#zones}, with a super mode
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] for a zone without one, or while the app shows the appliance off
        # @api public
        def set_super_mode(zone, on)
          require!(!zone.super_mode.nil?, 'the zone has no super mode')
          require!(!shown_off?(state), 'the app offers no super mode while the appliance is off')
          return put('State', 'ProcessAction', ProcessAction: process_action(zone, on)) if opcode?

          write_super_mode_duration(zone) if protocol_version == 201
          put('Cooling', "#{zone.number}/SuperMode", **switch(on))
        end

        # @param zone [Zone] one of {#zones}, with a fan
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] for a zone without one, or while the app hides the zones
        # @api public
        def set_fan(zone, on)
          require!(!zone.fan.nil?, 'the zone has no fan')
          require_zones_shown!
          put('Cooling', "#{zone.position}/Fan", **switch(on))
        end

        # @param zone [Zone] one of {#zones}, with VarioCool
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] for a zone without it, or while the app hides the zones
        # @api public
        def set_vario_cool(zone, on)
          require!(!zone.vario_cool.nil?, 'the zone has no VarioCool')
          require_zones_shown!
          put('Cooling', "#{zone.rank}/VarioCool", Value: on ? 1 : 2)
        end

        # @param name [Symbol] +:eco+, +:party+, +:holiday+, +:sabbath+ or +:child_proof+
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] unless the appliance lists values for that mode
        # @api public
        def set_mode(name, on)
          require!(modes[name]&.editable, "the appliance lists no #{name} mode to set")
          put('Cooling', MODES.fetch(name), Value: on ? 1 : 2)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an appliance without an ice maker
        # @api public
        def ice_maker=(on)
          require!(ice_maker?, 'the appliance has no ice maker')
          put('Cooling', 'IceMaker', Value: on ? 1 : 2)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] but on a wine unit the app lights
        # @api public
        def light=(on)
          require!(wine? && !rioja?, 'the app switches no light on this appliance')
          if state_light?
            put('State', 'Light', Light: on ? 1 : 2)
          else
            put('Cooling', 'AmbientLightState', **switch(on))
          end
        end

        # @param value [Integer] the mode's number on a BSH wine unit, the light's level on a Liebherr one
        # @return [void]
        # @raise [ActionUnavailableError] but on a BSH wine unit, or a protocol 203 one neither KWTUS nor Rioja
        # @api public
        def ambient_light_mode=(value)
          bsh = protocol_version == 200
          require!(wine? && !rioja? && (bsh || (protocol_version == 203 && !kwtus?)),
                   'the app sets no ambient light on this appliance')
          put('Cooling', bsh ? 'AmbientLightMode' : 'Light', Value: value)
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

        # @param zone [Zone] one of {#zones}
        # @param value [Integer] 0 switches the zone's light off
        # @return [void]
        # @raise [ActionUnavailableError] but on a KWTUS or Rioja wine unit with a presentation light, while the
        #   app's presenter light section shows
        # @api public
        def set_presentation_light_intensity(zone, value)
          require!(presentation_light?, 'the appliance has no presentation light')
          require!(presenter_light_shown?(state), 'the app shows no presentation light now')
          put('Cooling', "#{zone.rank}/PresentationLightIntensity", Value: value)
        end

        # @param level [Symbol] +:low+, +:medium+ or +:high+
        # @return [void]
        # @raise [ActionUnavailableError] but on a KWTUS or Rioja wine unit
        # @api public
        def humidity=(level)
          require!(rioja? || kwtus?, 'the appliance has no humidity control')
          put('Cooling', 'HumidityControl', Value: HUMIDITY.fetch(level))
        end

        # The app shows PerfectFresh for a +Step+ above 0 compared unsigned, so for any but 0.
        #
        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] on protocol 201, where the app reads none, or without a +Step+
        # @raise [ArgumentError] off +PerfectFresh+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def perfect_fresh=(value)
          setting = cooling['PerfectFresh']
          require!(protocol_version != 201 && !setting.to_h['Step'].to_i.zero?, 'the app shows no PerfectFresh here')
          require_offered!(value, picker(setting))
          put('Cooling', 'PerfectFresh', Value: value)
        end

        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] without +Humidifier+ or at its +Value+ -1, where the app hides the cell
        # @raise [ArgumentError] off +Humidifier+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def humidifier=(value)
          setting = cooling['Humidifier']
          require!(setting && setting['Value'] != -1, 'the app shows no humidifier')
          require_offered!(value, picker(setting))
          put('Cooling', 'Humidifier', Value: value)
        end

        # @param seconds [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] without +DoorAlarmTime+ or at its +Value+ -1, where the app hides the cell
        # @raise [ArgumentError] off +DoorAlarmTime+'s +Min+ to +Max+ by +Step+, which the app's picker offers
        # @api public
        def door_alarm_delay=(seconds)
          setting = cooling['DoorAlarmTime']
          require!(setting && setting['Value'] != -1, 'the app shows no door alarm delay')
          require_offered!(seconds, picker(setting))
          put('Cooling', 'DoorAlarmTime', Value: seconds)
        end

        private

        # @param resource [String] +Cooling+ or +State+
        # @param member [String] what follows it in the path
        # @param body [Hash{Symbol=>Object}]
        # @return [void]
        def put(resource, member, **body)
          send_request(:put, "/Devices/#{fab}/#{resource}/#{member}", body: JSON.generate(body))
        end

        # @param on [Boolean]
        # @return [Hash{Symbol=>Object}]
        def switch(on) = { Value: on ? 1 : 2, SetValues: [1, 2] }

        # @param zone [Zone]
        # @return [void]
        def write_super_mode_duration(zone)
          put('Cooling', "#{zone.number}/SuperModeDuration", Value: 720)
        rescue Error
          nil
        ensure
          @sleeper.call(0.5)
        end

        # @param zone [Zone]
        # @param on [Boolean]
        # @return [Integer]
        def process_action(zone, on) = SUPER_MODE_ACTIONS.fetch(zone.type, [0, 0])[on ? 0 : 1]
      end
    end
  end
end
