# frozen_string_literal: true

module Miele
  module Sdk
    class CoolingAppliance < Appliance
      # The zone and mode actions of the app's refrigeration module. The app checks nothing before them but the
      # protocol and the kind of appliance, and reads no +RemoteEnable+; the SDK refuses what the app offers no
      # control for.
      module Commands
        # +ProcessAction+ on and off for an Opcode fridge and freezer zone; the app sends 0 for any other.
        SUPER_MODE_ACTIONS = { fridge: [6, 7], freezer: [4, 5] }.freeze
        private_constant :SUPER_MODE_ACTIONS

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
