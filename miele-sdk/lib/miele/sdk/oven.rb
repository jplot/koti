# frozen_string_literal: true

module Miele
  module Sdk
    # An oven, steam oven or oven with microwave, which the Miele app's oven module handles (device types 12, 13,
    # 15, 31, 39 and 45).
    class Oven < Appliance
      # Switches the appliance on as the app's oven module does, waking it first when it sleeps. The app's
      # other families switch on in their own way.
      #
      # @return [void]
      # @raise [ResponseError] if the appliance still refuses after three attempts
      # @api public
      def power_on
        3.times do |attempt|
          rouse if attempt.positive?
          return write_dop2(power_leaf(4))
        rescue ResponseError => e
          raise unless e.status == 500 && attempt < 2
        end
      end

      # @return [void]
      # @raise [ResponseError] if the appliance refuses
      # @api public
      def power_off = write_dop2(power_leaf(1))

      # @return [Objects::Oven::GlobalDeviceContext] 1/1585, read without an index as the app observes it
      # @api public
      def context = object(Objects::Oven::GlobalDeviceContext)

      # @return [Objects::Oven::GlobalPsContext] 1/1574: the selected program and its parameters
      # @api public
      def program_context = object(Objects::Oven::GlobalPsContext)

      # @param second_cavity [Boolean] a double oven's second cavity, read on 1/392
      # @return [Objects::Oven::GlobalNtfctnShow] 1/131: infos, messages, errors and queries
      # @api public
      def notifications(second_cavity: false)
        klass = Objects::Oven::GlobalNtfctnShow
        object(klass, klass::ADDRESSES.fetch(second_cavity ? 1 : 0))
      end

      # @return [Objects::Oven::GlobalProgramGroupsComplete] 1/1599: the programs the oven offers
      # @api public
      def program_groups = object(Objects::Oven::GlobalProgramGroupsComplete)

      # The app reads them along a chain: each instance gives the next one's idx1 as its idx2, the last its own.
      #
      # @return [Array<Objects::Oven::GlobalOpProgramName>] the own programs, from 1/109
      # @api public
      def own_programs
        programs = [] #: Array[untyped]
        idx1 = 0
        loop do
          leaf = dop2(1, 109, idx1:, idx2: 1)
          programs << Objects::Oven::GlobalOpProgramName.from(leaf.fields)
          return programs if leaf.idx1 == leaf.idx2

          idx1 = leaf.idx2
        end
      end

      # @return [Array(Objects::Oven::GlobalOpProgramInfoCA, Array<Objects::Oven::GlobalOpProgramStepInfoCA>)] the
      #   running own program (2/213) and its steps (2/214, idx1 0 on)
      # @api public
      def program_steps
        info = object(Objects::Oven::GlobalOpProgramInfoCA)
        step = Objects::Oven::GlobalOpProgramStepInfoCA
        [info, Array.new(info.amount_of_steps.to_i) { object(step, [2, 214, it, 1]) }]
      end

      # @return [Objects::Oven::GlobalDeviceContext2ndDevice] 1/391: a double oven's second cavity
      # @api public
      def second_cavity_context = object(Objects::Oven::GlobalDeviceContext2ndDevice)

      # @return [Float, nil] °C, nil when no program sets it
      # @api public
      def target_temperature = celsius(:temperature)

      # @return [Float, nil] °C of the core probe, nil when no program sets it
      # @api public
      def core_target_temperature = celsius(:core_temperature)

      # @return [Array<Integer>] the user requests the oven offers now, numbered as the app numbers them
      # @api public
      def supported_requests
        Array(context.supported_user_requests).map { Objects::Oven::GlobalEnumUserRequestId.to_i(it) }
      end

      private

      # @param parameter [Symbol] a member of +GLOBAL_PS_ContextParaCA+, in hundredths of °C
      # @return [Float, nil]
      def celsius(parameter)
        value = program_context.context_para_ca&.public_send(parameter)
        value&.current_value&.then { it / 100.0 }
      end

      # The appliance state on 2/1586: 4 switches on, 1 off.
      #
      # @param state [Integer]
      # @return [Dop2::Leaf]
      def power_leaf(state)
        Dop2::Leaf.new(unit: 2, attribute: 1586, idx1: 0, idx2: 0,
                       fields: { 1 => Dop2::Field.new(type: :e8, value: state) })
      end

      # A sleeping appliance answers 500 to the state write; the app then sends DeviceAction 2, waits 3 s and
      # tries again, with no limit: three attempts here.
      #
      # @return [void]
      def rouse
        begin
          wake
        rescue ResponseError
          nil
        end
        @sleeper.call(3)
      end
    end
  end
end
