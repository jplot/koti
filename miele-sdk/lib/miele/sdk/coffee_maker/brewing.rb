# frozen_string_literal: true

module Miele
  module Sdk
    class CoffeeMaker < Appliance
      # Drinks and Barista as the app's coffee module dispenses them on a DOP2 coffee maker: PS_Select 2/1577
      # through ModifyDop2Message, after its IsDrinkDispensableStatusRule.
      module Brewing
        # Barista's program id.
        BARISTA = 24_407
        # Each variant's least software ids (2/17, then 1/17) for two cups or a double shot.
        ONE_TOUCH_IDS = { cm7: [5374, 0], cm6f: [5714, 5713], cva: [6228, 6226], cva_ref2: [6228, 6227] }.freeze
        # The app's program info source fails, and its drink rule and stop button with it, when 1574 lacks one of these.
        PROGRAM_MEMBERS = %i[prog_id prog_phase prog_sub_phase programtype progress_bar].freeze
        private_constant :ONE_TOUCH_IDS, :PROGRAM_MEMBERS

        # @param drink [Integer, Symbol] its program id
        # @param two_cups [Boolean]
        # @param double_shot [Boolean]
        # @return [void]
        # @raise [ActionUnavailableError] on a CVA6000, or unless the app's rule allows a drink: mobile start, no
        #   information or query shown, no drink, Barista or care program running; two cups or a double shot also
        #   need the software ids the app requires
        # @raise [ArgumentError] for program 0 or an id the app does not define, or when 2/1577 carries no coffee
        #   parameters
        # @api public
        def brew(drink, two_cups: false, double_shot: false)
          require!(dop2?, 'the app brews nothing on a CVA6000')
          require_drink!(drink)
          require_dispensable!
          if two_cups || double_shot
            require!(one_touch?, 'the coffee maker takes two cups or a double shot only from newer software')
          end
          write_drink(drink, two_cups, double_shot)
        end

        # @return [void]
        # @raise [ActionUnavailableError] unless a CM6F, CVA or Ref2 that lists Barista among its special beverages
        #   is on (Status 2 or 3) under remote control without local control, runs no program and shows no
        #   information
        # @api public
        def start_barista
          require!(barista_entry?(state), 'the coffee maker cannot start Barista now')
          modify_dop2(family::GlobalPsSelect, 2, 1577, 0, 1) { it.with(prog_id: BARISTA, selection_type: 0) }
        end

        private

        # The app writes both flags every time.
        #
        # @param drink [Integer, Symbol]
        # @param two_cups [Boolean]
        # @param double_shot [Boolean]
        # @return [void]
        # @raise [ArgumentError] when 2/1577 carries no coffee parameters
        def write_drink(drink, two_cups, double_shot)
          modify_dop2(family::GlobalPsSelect, 2, 1577, 0, 1) do |select|
            para = select.selection_para_co
            raise ArgumentError, '2/1577 carries no coffee parameters' unless para

            select.with(prog_id: drink, selection_type: 0,
                        selection_para_co: para.with(drink_one_touch_for_two: two_cups, drink_double_shot: double_shot))
          end
        end

        # DrinkExtensions.ToGen7ProgramId and ToCm7ProgramId refuse 0 and an id the enum does not define.
        #
        # @param drink [Integer, Symbol]
        # @return [void]
        # @raise [ArgumentError]
        def require_drink!(drink)
          id = family::GlobalEnumPrgId.to_i(drink)
          raise ArgumentError, "no drink #{drink}" if id.zero? || !family::GlobalEnumPrgId.from(id).is_a?(Symbol)
        end

        # @return [void]
        # @raise [ActionUnavailableError]
        def require_dispensable!
          program = program_context&.prog_attributes_cca
          require!(complete?(program) && mobile_start_on?(state) && !notified? && !busy?(program),
                   'the coffee maker cannot dispense a drink now')
        end

        # @param state [State]
        # @return [Boolean] remote control and mobile start without local control
        def mobile_start_on?(state)
          state.remote_control? == true && state.local_control? != true && state.mobile_start? == true
        end

        # BaristaAssistantEntryPointRule; the start page's further message check is not traced.
        #
        # @param state [State]
        # @return [Boolean]
        def barista_entry?(state)
          %i[cm6f cva cva_ref2].include?(variant) && [2, 3].include?(state.raw['Status']) &&
            state.remote_control? == true && state.local_control? != true && program_id.zero? && !informed? &&
            barista?
        end

        # @return [Boolean] any information or query with an id
        def notified?
          queries = notifications.queries.to_a.map { notified_id(family::GlobalEnumNtfctnQueryId, it.id) }
          informed? || queries.any?(&:positive?)
        end

        # @return [Boolean] any information with an id
        def informed?
          notifications.infos.to_a.any? { notified_id(family::GlobalEnumNtfctnInfoId, it.id).positive? }
        end

        # @param enum [Module]
        # @param id [Integer, Symbol, nil]
        # @return [Integer]
        def notified_id(enum, id) = id.nil? ? 0 : enum.to_i(id)

        # @param program [Data] +ProgAttributesCCA+
        # @return [Boolean] a drink, Barista or a care program running
        def busy?(program)
          id = family::GlobalEnumPrgId.to_i(program.prog_id)
          dispensing?(id, phase_of(program)) || (gen7? && id == BARISTA) || care?(id)
        end

        # @param program [Data] +ProgAttributesCCA+
        # @return [Integer]
        def phase_of(program) = family::GlobalEnumPPhaseId.to_i(program.prog_phase)

        # @param program [Data] +ProgAttributesCCA+
        # @return [Integer]
        def sub_phase_of(program) = family::GlobalEnumSubPPhaseId.to_i(program.prog_sub_phase)

        # @param program [Data, nil] +ProgAttributesCCA+
        # @return [Boolean] whether it carries every member the app reads
        def complete?(program) = !program.nil? && PROGRAM_MEMBERS.none? { program.public_send(it).nil? }

        # @param id [Integer]
        # @param phase [Integer]
        # @return [Boolean]
        def dispensing?(id, phase)
          return (24_001..24_031).cover?(id) if variant == :cm7

          (24_000..24_406).cover?(id) && phase != 10_003
        end

        # On a CM7 the app does not count programs 24060 and 24063 as care.
        #
        # @param id [Integer]
        # @return [Boolean]
        def care?(id)
          operation = combi_state&.operation_state
          return false if operation.nil? || family::GlobalEnumOperationState.to_i(operation) != 8

          variant != :cm7 || ![24_060, 24_063].include?(id)
        end

        # IsOneTouchDoubleShotSupportedRule; a CM7 reads no 1/17.
        #
        # @return [Boolean]
        def one_touch?
          system, board = ONE_TOUCH_IDS[variant]
          return false unless system && board

          main_id(2) >= system && (variant == :cm7 || main_id(1) >= board)
        end

        # @param unit [Integer]
        # @return [Integer] the first software id of +unit+/17, 0 without one
        def main_id(unit)
          entry = object(Objects::CoffeeGen7::SysSoftwareIds, [unit, 17, 0, 0]).sw_ids.to_a.first
          entry ? entry.id.to_i : 0
        end

        # The app takes the last 1/1599 small group starting at 24400; Barista is bit 7 of its first mask word.
        #
        # @return [Boolean]
        def barista?
          groups = object(Objects::CoffeeGen7::GlobalProgramGroupsComplete, [1, 1599, 0, 1]).small_ones.to_a
          group = groups.rfind { it.start == 24_400 }
          !group.nil? && group.mask.to_a.first.to_i[7] == 1
        end
      end
    end
  end
end
