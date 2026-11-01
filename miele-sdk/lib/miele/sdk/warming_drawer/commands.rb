# frozen_string_literal: true

module Miele
  module Sdk
    class WarmingDrawer < Appliance
      # The actions of the app's drawer module, each after the rule the app enables it by: Dop1 writes on 1101 and
      # 9781, which raise {NotAcceptedError} on an Ack other than 1, and the cup warm-up in +services+.
      module Commands
        # The app's settings switch shows off, and so offers on, in these states only.
        #
        # @return [void]
        # @raise [ActionUnavailableError] without mobile start, under local control, or unless off, off with the door
        #   open, finished or idle
        # @api public
        def power_on
          state = self.state
          require!(switchable?(state) && %i[off off_and_door_open finished idle].include?(drawer_state(state)),
                   'the drawer cannot be switched on now')
          write_device_action(2)
        end

        # The app's settings switch, action bar and dashboard each allow it; the SDK when any of them does.
        #
        # @return [void]
        # @raise [ActionUnavailableError] without mobile start, under local control, or off, off with the door open,
        #   finished or not connected
        # @api public
        def power_off
          state = self.state
          off = %i[off off_and_door_open finished not_connected].include?(drawer_state(state))
          require!(switchable?(state) && !off, 'the drawer cannot be switched off now')
          write_device_action(3)
        end

        # @param id [Integer] 1 cups, 2 plates, 3 food, 4 low-temperature cooking
        # @return [void]
        # @raise [ActionUnavailableError] unless under remote control and mobile start without local control, the
        #   drawer on, running or off
        # @api public
        def select_program(id)
          raise ArgumentError, 'the drawer runs programs 1 to 4' unless (1..4).cover?(id)

          state = self.state
          require!(controllable?(state) && %i[on running off off_and_door_open].include?(drawer_state(state)),
                   'the drawer takes a program only when on, running or off')
          write_process_data(id, 0, 0)
        end

        # The app re-sends the remaining time +State+ shows.
        #
        # @param celsius [Integer] one of the program's temperatures (see {#programs})
        # @return [void]
        # @raise [ActionUnavailableError] without mobile start, under local control, or without a program
        # @raise [ArgumentError] for a temperature the program does not offer
        # @api public
        def target_temperature=(celsius)
          state = self.state
          require!(switchable?(state), 'the drawer takes a temperature only under mobile start')
          steps = program(state)&.temperatures.to_a
          require!(!steps.empty?, 'the drawer runs no program to set')
          raise ArgumentError, "#{celsius} °C is not one of #{steps}" unless steps.include?(celsius)

          write_process_data(state.raw['ProgramID'].to_i, remaining_minutes(state), celsius)
        end

        # The app keeps to the program's maximum and re-sends the target temperature +State+ shows; 0 resets it.
        #
        # @param minutes [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] unless under remote control and mobile start without local control, the
        #   program set or running (Status 3 to 6)
        # @api public
        def remaining_time=(minutes)
          state = self.state
          require!(controllable?(state) && [3, 4, 5, 6].include?(state.raw['Status']),
                   'the drawer takes a remaining time only while its program is set or runs')
          max_hours = program(state)&.max_hours
          minutes = [minutes, max_hours * 60].min if max_hours
          write_process_data(state.raw['ProgramID'].to_i, minutes, target_celsius(state))
        end

        # @param coffee_maker [String, nil] the fab of a coffee maker the drawer lists, nil to stop
        # @return [void]
        # @raise [ActionUnavailableError] while the drawer is disconnected or offers no cup warm-up
        # @raise [ArgumentError] for a coffee maker the drawer does not list
        # @api public
        def cups_warm_up_source=(coffee_maker)
          warm_up = cups_warm_up || {}
          require!(state.raw['Status'] != 255 && warm_up['available'] == true, 'the drawer offers no cup warm-up')
          if coffee_maker && !Array(warm_up['availableSourceDeviceIDs']).include?(coffee_maker)
            raise ArgumentError, "#{coffee_maker} is not a coffee maker the drawer lists"
          end

          body = coffee_maker ? { activated: true, sourceDeviceId: coffee_maker } : { activated: false }
          send_request(:put, "/Devices/#{fab}/services/CupsWarmUp", body: JSON.generate(body))
        end

        private

        # @param state [State]
        # @return [Boolean] mobile start without local control
        def switchable?(state) = state.mobile_start? == true && state.local_control? != true

        # @param state [State]
        # @return [Boolean] remote control and mobile start without local control
        def controllable?(state) = switchable?(state) && state.remote_control? == true

        # @param action [Integer] 2 on, 3 off
        # @return [void]
        def write_device_action(action)
          section = blank(Objects::Drawer::DeviceAction::DeviceActionWriteSection).with(struktur_version: 1, action:)
          write_dop1_object(Objects::Drawer::DeviceAction, section, type: Dop1::WRITE)
        end

        # The app writes the hours of the time left without its days.
        #
        # @param program [Integer]
        # @param minutes [Integer]
        # @param celsius [Integer]
        # @return [void]
        def write_process_data(program, minutes, celsius)
          section = blank(Objects::Drawer::ServiceExtEswProcessData::ServiceExtEswProcessDataWriteSection)
                    .with(struktur_version: 1, betriebsart: program, restzeit_minuten: minutes % 60,
                          restzeit_stunden: minutes / 60 % 24, prozess_temperatur: celsius)
          write_dop1_object(Objects::Drawer::ServiceExtEswProcessData, section, type: Dop1::WRITE)
        end

        # @param state [State]
        # @return [Program, nil] the program +State+ shows
        def program(state) = programs.find { it.id == state.raw['ProgramID'] }

        # @param state [State]
        # @return [Integer] +RemainingTime+ [h, m] in minutes, 0 without both
        def remaining_minutes(state)
          hours, minutes = state.raw['RemainingTime']
          hours && minutes ? (hours * 60) + minutes : 0
        end

        # @param state [State]
        # @return [Integer] whole °C, 255 outside 0 to 100 as the app sends it
        def target_celsius(state)
          celsius = (state.raw['TargetTemperature']&.first.to_i / 100.0).truncate
          state.raw['TargetTemperature'] && (0..100).cover?(celsius) ? celsius : 255
        end
      end
    end
  end
end
