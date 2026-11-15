# frozen_string_literal: true

module Miele
  module Sdk
    class Hood < Appliance
      # The hood actions the app sends in more than one protocol, each by the route {Wire} picks.
      module Commands
        FAN_LEVELS = (0..5)
        RUN_ON_TIMES = [0, 5, 15].freeze
        FRAGRANCE_SETTINGS = { stop: 0, start: 1, miele_program: 2 }.freeze
        private_constant :FAN_LEVELS, :RUN_ON_TIMES, :FRAGRANCE_SETTINGS

        # {Readings#fan_settable?} gives whether the app sets it: never while the hood's screen is pushed in.
        #
        # @param level [Integer] 0 (off) to 3, 4 (boost) or 5 (interval)
        # @return [void]
        # @raise [ArgumentError] if the level is out of range
        # @raise [ActionUnavailableError] on a hood of a protocol the app has no fan action for
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def fan_level=(level)
          raise ArgumentError, "fan level #{level} is out of 0..5" unless FAN_LEVELS.cover?(level)

          case route(:fan)
          when :dop1 then write_dop1(Dop1.fan_level(level))
          when :opcode then opcode_twice("10000608010#{level}000000")
          else write_dop2(hood_select(1 => level))
          end
        end

        # @param minutes [Integer] such as one of {#fan_run_on_times}
        # @return [void]
        # @raise [ArgumentError] for minutes a Dop1 or Opcode hood's byte, or a DOP2 hood's u16, does not hold
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def fan_run_on_time=(minutes)
          case route(:fan)
          when :dop1 then write_dop1(Dop1.fan_run_on_time(minutes))
          when :opcode then opcode(format('10000609%02X00000000', Dop1.unsigned(minutes, 8)))
          else write_dop2(hood_select(2 => minutes))
          end
        end

        # @return [Array<Integer>] the run-on times, in minutes, the app's picker offers
        # @api public
        def fan_run_on_times = RUN_ON_TIMES

        # @param on [Boolean]
        # @return [void]
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def main_light=(on)
          case route(:fan)
          when :dop1 then write_dop1(Dop1.main_light(on))
          when :opcode then send_request(:put, "/Devices/#{fab}/State/", body: JSON.generate('Light' => on ? '1' : '2'))
          else dop2_user_request(on ? 13 : 14)
          end
        end

        # {Readings#lights} gives whether the hood has one.
        #
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] when the hood drives its lights by Opcode, which has no request for a
        #   second light
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def ambient_light=(on)
          path = route(:fan)
          require!(path != :opcode, 'an Opcode hood has no request for an ambient light')
          request = on ? 20_001 : 20_002
          path == :dop1 ? dop1_ambient_light(on) : dop2_user_request(request)
        end

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def ambient_light_while_cooking=(on)
          value = on ? 1 : 0
          route(:setting) == :dop1 ? write_setting(40_029, value) : write_sf(9001, value)
        end

        # @return [void]
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def reset_grease_filter = reset_filter(40_012, 20_009, '0B0003000300')

        # @return [void]
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def reset_charcoal_filter = reset_filter(40_013, 20_008, '0B0003000400')

        # @param action [Symbol] +:start+ (20 minutes), +:stop+ or +:miele_program+
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood
        # @raise [ArgumentError] for another action
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def fragrance(action)
          value = FRAGRANCE_SETTINGS.fetch(action) { raise ArgumentError, "no fragrance action #{action.inspect}" }
          return dop1_fragrance(action) if route(:setting) == :dop1

          write_sf(9009, value)
        end

        # @return [Boolean, nil] whether the app offers {#fragrance}: PF 40028 bit 7 on a Dop1 hood, function bit 5
        #   of ExtendedState on a DOP2 one, never on an Opcode one; nil when the DOP2 hood serves no ExtendedState
        # @api public
        def fragrance_supported?
          case protocol_version
          when 2 then setting(40_028).to_i[7] == 1
          when 3, 4 then extended&.then { second_functions(it)[5] == 1 }
          else false
          end
        end

        # {Readings#auto_refresh_supported?} gives whether the app offers it.
        #
        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on an Opcode hood
        # @raise [NotAcceptedError] when a Dop1 hood answers an Ack other than 1
        # @api public
        def auto_refresh=(on)
          value = on ? 1 : 0
          route(:setting) == :dop1 ? write_setting(40_023, value) : write_sf(9007, value)
        end

        # {Readings#color_flow} gives whether the hood has ColorFlow.
        #
        # @param active [Boolean]
        # @param interval [Integer] seconds, such as one of {#color_flow_intervals}
        # @return [void]
        # @raise [NotFoundError] when the hood answers 404
        # @api public
        def configure_color_flow(active:, interval: 10)
          body = JSON.generate('active' => active, 'intervalDurationSeconds' => interval)
          send_request(:put, "/Devices/#{fab}/ColorFlow", body:)
        end

        # @return [Array<Integer>] the ColorFlow intervals, in seconds, the app's picker offers
        # @api public
        def color_flow_intervals = COLOR_FLOW_INTERVALS

        # Con@ctivity Plus: the hood follows one more hob. {Readings#connectivity_plus} gives whether the app offers
        # it.
        #
        # @param hob [String] its fabrication number
        # @return [void]
        # @api public
        def connect_hob(hob) = update_connectivity_plus { (it + [hob]).uniq }

        # @param hob [String] its fabrication number
        # @return [void]
        # @api public
        def disconnect_hob(hob) = update_connectivity_plus { it - [hob] }

        # A Dop1 or Opcode hood wakes when its State is written back, the light as it is, while +State+ shows it
        # off; only an answer carrying "Success" means woken (DefaultWakeUpAction). DOP2 takes +DeviceAction+ 2.
        #
        # @return [void]
        # @raise [ResponseError] when the hood refuses the write, 400 included
        # @raise [NotAcceptedError] when a Dop1 or Opcode hood answers without "Success"
        # @api public
        def wake
          return super if [3, 4].include?(protocol_version)

          state = self.state
          return unless state.status == :off

          answer = command(Schema::DeviceState.new(light: state.raw['Light'])).body
          raise NotAcceptedError, "the hood answered #{answer.inspect} to its wake" unless answer.include?('"Success"')
        end

        # @return [Boolean] whether the app wakes the hood: a DOP2 one always, a Dop1 or Opcode one while +State+
        #   shows it off
        # @api public
        def wake_offered? = [3, 4].include?(protocol_version) || state.status == :off

        private

        # The app changes one hob in the list +services+ shows and derives +activated+ from what is left
        # (UpdateConactivityPlusSettingsHelper).
        #
        # @yieldparam sources [Array<String>] the hobs followed
        # @yieldreturn [Array<String>] those to follow
        # @return [void]
        def update_connectivity_plus
          sources = yield Array(connectivity_plus&.sources)
          body = JSON.generate('activated' => sources.any?, 'sourceDeviceIds' => sources)
          send_request(:put, "/Devices/#{fab}/services/ConnectivityPlus", body:)
        end

        # @param pf_id [Integer] its Dop1 setting
        # @param request [Integer] its DOP2 user request
        # @param opcode_request [String] its Oc85 request
        # @return [void]
        def reset_filter(pf_id, request, opcode_request)
          case route(:filter)
          when :dop1 then write_setting(pf_id, 1)
          when :opcode then opcode(opcode_request)
          else dop2_user_request(request)
          end
        end
      end
    end
  end
end
