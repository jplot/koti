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
        # @raise [ActionUnavailableError] unless the app's start rule allows it: no info 700, mobile start, the door
        #   closed, request 1 offered, and the dishwasher ready (Status 3, or 4 awake)
        # @api public
        def start
          state = checked_state
          require!(mobile?(state) && !state.door_open? && offered?(:start) && ready?(state),
                   'the dishwasher cannot start now')
          run(state, :start)
        end

        # @return [void]
        # @raise [ActionUnavailableError] unless it runs (Status 5) under mobile start and offers pause
        # @api public
        def pause
          state = checked_state
          require!(mobile?(state) && offered?(:pause) && status(state) == 5, 'the dishwasher cannot pause now')
          run(state, :pause)
        end

        # The app resumes with request 1.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless it is paused (Status 6) under mobile start and offers start
        # @api public
        def resume
          state = checked_state
          require!(mobile?(state) && offered?(:start) && status(state) == 6, 'the dishwasher cannot resume now')
          run(state, :resume)
        end

        # @return [void]
        # @raise [ActionUnavailableError] see {#cancel}
        # @api public
        def stop = stop_with(:stop)

        # The app stops or cancels without mobile start, only not locked.
        #
        # @return [void]
        # @raise [ActionUnavailableError] unless it runs, pauses or waits awake, offers the request and shows no
        #   info 700
        # @api public
        def cancel = stop_with(:cancel)

        # @param prog_id [Integer, Symbol]
        # @return [void]
        # @api public
        def select_program(prog_id)
          return dop1_select(prog_id) unless dop2?

          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 0, 0]) { it.with(prog_id:, selection_type: 0) }
        end

        # Each extra this model writes is set on when named, off otherwise; the others stay as read.
        #
        # @param selected [Array<Symbol>] among +:quick+, +:express+, +:hot_zone+, +:clean+, +:dry+, +:bottle_clean+
        #   and +:special_dry+ on DOP2, +:short+, +:eco+, +:dry+, +:intensive_low+, +:soak+, +:prerinse+ and
        #   +:additional_drying+ on Dop1, as the model takes them
        # @return [void]
        # @raise [ArgumentError] for an extra the app does not write on this model
        # @api public
        def set_extras(*selected)
          handled = EXTRAS.fetch(extras_kind)
          raise ArgumentError, "no #{(selected - handled).join(', ')} extra here" unless (selected - handled).empty?
          return dop1_extras(selected) if extras_kind == :dop1

          context = object(Objects::Dishwasher::GlobalPsContext, [2, 1574, 0, 0])
          modify(Objects::Dishwasher::GlobalPsSelect, [2, 1577, 0, 0]) do |select|
            with_extras(select, context, handled.to_h { [it, selected.include?(it)] })
          end
        end

        # @param on [Boolean]
        # @return [void]
        # @api public
        def auto_dos=(on)
          modify(Objects::Dishwasher::GlobalSfValue, [2, 105, 20_052, 1]) { it.with(current_value: on ? 1 : 0) }
        end

        # @param id [Integer] 20078, 20002, 20010, 20028, 20022 or 20027 on a G38, G58 or G7; 20064 on a PFD10
        # @param value [Integer]
        # @return [void]
        # @raise [ActionUnavailableError] for a setting the app does not write on this model
        # @api public
        def write_setting(id, value)
          require!(settable?(id), "the app writes no setting #{id} on this dishwasher")
          modify(Objects::Dishwasher::GlobalSfValue, [2, 105, id, 1]) { it.with(current_value: value) }
        end

        # @return [void]
        # @raise [ActionUnavailableError] without remote control
        # @api public
        def leave_abort
          require_dop2!
          require!(state.remote_control?, 'the dishwasher takes it only under remote control')
          modify(Objects::Dishwasher::GlobalDeviceCombiState, [2, 1586, 0, 1]) do |combi|
            combi.with(appliance_state: 4, operation_state: 5, process_state: 1)
          end
        end

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

        # @param request [Symbol]
        # @return [void]
        def stop_with(request)
          state = checked_state
          running = [5, 6].include?(status(state)) || (status(state) == 4 && [1, 255].include?(standby(state)))
          require!(!locked_in?(state) && offered?(request) && running, "the dishwasher cannot #{request} now")
          run(state, request)
        end

        # @param state [State]
        # @param name [Symbol] a key of {ACTIONS}
        # @return [void]
        def run(state, name)
          request, process_action = ACTIONS.fetch(name)
          dop2? ? dop2_user_request(request) : dop1_process_action(state, process_action)
        end

        # The app reads info 700 from 2/131, on DOP2 only.
        #
        # @return [State]
        # @raise [ActionUnavailableError] while a DOP2 dishwasher shows info 700
        def checked_state
          require_no_info700! if dop2?
          state
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
                                                   prog_extras: para.prog_extras.with(**extras)))
        end

        # @return [void]
        # @raise [ActionUnavailableError] on a Dop1 dishwasher
        def require_dop2! = require!(dop2?, 'only a DOP2 dishwasher takes this, as in the app')
      end
    end
  end
end
