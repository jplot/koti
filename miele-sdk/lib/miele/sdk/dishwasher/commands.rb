# frozen_string_literal: true

module Miele
  module Sdk
    class Dishwasher < Appliance
      # The actions of the app's dishwasher module, after the checks of its Mapping rules ({Rules}): on a DOP2
      # dishwasher each object is read, changed and written back with no index in the path; a Dop1 one takes
      # +ProcessAction+ and Dop1 objects ({Dop1Commands}).
      module Commands
        REDESIGNED = %w[G703 G721 G723 G713 G740 G743 G760 G762 G771 G773 G793 G707 G726 G729 G738 G718 G745 G748
                        G749 G765 G767 G776 G778 G779 G798].freeze
        EXTRAS = { redesigned: %i[quick express hot_zone clean dry bottle_clean], pfd10: %i[special_dry],
                   other: %i[express hot_zone clean dry],
                   dop1: %i[short eco dry intensive_low soak prerinse additional_drying] }.freeze
        SETTINGS = [20_078, 20_002, 20_010, 20_028, 20_022, 20_027].freeze
        # The DOP2 user request and the Dop1 +ProcessAction+ of each: the app pauses, resumes and stops a Dop1
        # dishwasher with 2.
        ACTIONS = { start: [1, 1], pause: [3, 2], resume: [1, 2], stop: [2, 2], cancel: [52, 128] }.freeze
        private_constant :REDESIGNED, :EXTRAS, :SETTINGS, :ACTIONS

        # @return [void]
        # @api public
        def start = run(:start)

        # @return [Boolean] whether the app's start rule allows {#start}: no info 700, mobile start, the door
        #   closed, request 1 offered, and the dishwasher {Rules#ready? ready}
        # @api public
        def start_offered?
          return false if info700?

          state = self.state
          mobile?(state) && !state.door_open? && offered?(:start) && ready?(state)
        end

        # @return [void]
        # @api public
        def pause = run(:pause)

        # @return [Boolean] whether the app offers {#pause}: no info 700, a program running (Status 5) under mobile
        #   start, and pause offered
        # @api public
        def pause_offered?
          return false if info700?

          state = self.state
          mobile?(state) && offered?(:pause) && status(state) == 5
        end

        # The app resumes with request 1.
        #
        # @return [void]
        # @api public
        def resume = run(:resume)

        # @return [Boolean] whether the app offers {#resume}: no info 700, a program paused (Status 6) under mobile
        #   start, and start offered
        # @api public
        def resume_offered?
          return false if info700?

          state = self.state
          mobile?(state) && offered?(:start) && status(state) == 6
        end

        # The app's Stop quick action is on while either Stop or Cancel is offered, and sends Stop.
        #
        # @return [void]
        # @api public
        def stop = run(:stop)

        # @return [Boolean] whether the app's Stop quick action is on: no info 700, a program running, paused or
        #   waiting awake, stop or cancel offered, and the dishwasher not locked
        # @api public
        def stop_offered?
          return false if info700?

          state = self.state
          running = [5, 6].include?(status(state)) || (status(state) == 4 && [1, 255].include?(standby(state)))
          offered = offered?(:stop) || offered?(:cancel)
          !locked_in?(state) && offered && running
        end

        # The app sends Cancel as the second button of its details bar (ActionBarComponentsRule). Its other Cancel,
        # the button that reverts the selected extras when no action is offered, is left out.
        #
        # @return [void]
        # @api public
        def cancel = run(:cancel)

        # @return [Boolean] whether the app's details bar offers {#cancel}: no info 700, the bar
        #   {Rules#details_bar? shown}, neither pause nor stop ahead of cancel, and mobile start, a program running
        #   or paused, or one waiting under remote control
        # @api public
        def cancel_offered?
          return false if info700?

          state = self.state
          details_bar?(state) && second_button(supported_requests) == :cancel && second_button_on?(state)
        end

        # @param prog_id [Integer, Symbol]
        # @return [void]
        # @api public
        def select_program(prog_id)
          return dop1_select(prog_id) unless dop2?

          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 0, 0]) { it.with(prog_id:, selection_type: 0) }
        end

        # Each extra the app writes on this model is set on when named, off otherwise; another one named is set on,
        # and the others stay as read.
        #
        # @param selected [Array<Symbol>] members of +GLOBAL_PS_ExtrasDW+ on DOP2 (+:quick+, +:express+,
        #   +:hot_zone+, +:clean+, +:dry+, +:special_dry+, +:dry_plus+, +:auto_open+, +:bottle_clean+); +:short+,
        #   +:eco+, +:dry+, +:intensive_low+, +:soak+, +:prerinse+ or +:additional_drying+ on Dop1
        # @return [void]
        # @raise [ArgumentError] for an extra the dishwasher's object has no place for, or when 2/1577 carries none
        # @api public
        def set_extras(*selected)
          return dop1_extras(selected) if extras_kind == :dop1

          context = object(Objects::Dishwasher::GlobalPsContext, [2, 1574, 0, 0])
          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 0, 0]) do |select|
            with_extras(select, context, offered_extras.to_h { [it, false] }.merge(selected.to_h { [it, true] }))
          end
        end

        # @return [Array<Symbol>] the extras the app writes on this model, as {#set_extras} names them
        # @api public
        def offered_extras = EXTRAS.fetch(extras_kind)

        # @param on [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no 2/105 to write
        # @api public
        def auto_dos=(on)
          require_dop2!
          modify(Objects::Dishwasher::GlobalSfValue, [2, 105, 20_052, 1]) { it.with(current_value: on ? 1 : 0) }
        end

        # @param id [Integer] a +GLOBAL_EnumSfId+ value, such as one of {#offered_settings}
        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no 2/105 to write
        # @api public
        def write_setting(id, value)
          require_dop2!
          modify(Objects::Dishwasher::GlobalSfValue, [2, 105, id, 1]) { it.with(current_value: value) }
        end

        # @return [Array<Integer>] the settings the app writes on this model: 20078, 20002, 20010, 20028, 20022 and
        #   20027 on a DOP2 G38, G58 or G7; 20064 on a PFD10
        # @api public
        def offered_settings = [*SETTINGS, 20_064].select { settable?(it) }

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no 2/1586 to write
        # @api public
        def leave_abort
          require_dop2!
          modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 1]) do |combi|
            combi.with(appliance_state: 4, operation_state: 5, process_state: 1)
          end
        end

        # @return [Boolean] whether the app offers {#leave_abort}: a DOP2 dishwasher under remote control
        # @api public
        def leave_abort_offered? = dop2? && state.remote_control? == true

        # @param info [Integer, Symbol] the info shown
        # @param option [Integer, Symbol] one of its options
        # @return [void]
        # @api public
        def acknowledge(info:, option:)
          require_dop2!
          modify(Objects::Dishwasher::GlobalNtfctnAcknowledge, [2, 138, 0, 1]) { it.with(info:, ack_option: option) }
        end

        private

        # @return [Symbol] +:pfd10+, +:dop1+, +:redesigned+ or +:other+
        def extras_kind
          return :pfd10 if pfd10?
          return :dop1 unless dop2?

          REDESIGNED.any? { tech_type.to_s.start_with?(it) } ? :redesigned : :other
        end

        # @return [Boolean]
        def pfd10? = tech_type.to_s.start_with?('PFD10')

        # @param id [Integer]
        # @return [Boolean]
        def settable?(id)
          return pfd10? if id == 20_064

          dop2? && SETTINGS.include?(id) && %w[G38 G58 G7].any? { tech_type.to_s.start_with?(it) }
        end

        # @param name [Symbol] a key of {ACTIONS}
        # @return [void]
        def run(name)
          request, process_action = ACTIONS.fetch(name)
          dop2? ? dop2_user_request(request) : dop1_process_action(state, process_action)
        end

        # @param select [Data] 2/1577
        # @param context [Data] 2/1574
        # @param extras [Hash{Symbol=>Boolean}]
        # @return [Data]
        def with_extras(select, context, extras)
          prog_id = context.prog_attributes_dwtdwm&.prog_id
          select = select.with(prog_id:) if prog_id
          select = select.with(selection_type: 2)
          para = select.selection_para_dw
          return select unless para

          mode = context.context_para_dw&.delayed_start_mode&.current_value || 2
          select.with(selection_para_dw: para.with(delayed_start_mode: mode, delayed_start: 0,
                                                   prog_extras: read_extras(para).with(**extras)))
        end

        # @param para [Data] 2/1577's +selection_para_dw+
        # @return [Data] its +prog_extras+
        # @raise [ArgumentError] when it carries none
        def read_extras(para) = para.prog_extras || raise(ArgumentError, 'this dishwasher carries no extras in 2/1577')

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher, whose protocol has no DOP2 leaf to write
        def require_dop2! = require!(dop2?, 'a Dop1 dishwasher has no DOP2 leaf to write')
      end
    end
  end
end
