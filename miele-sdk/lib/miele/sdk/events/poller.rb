# frozen_string_literal: true

module Miele
  module Sdk
    module Events
      # A DOP2 object read again and again, as the app polls the leaves it does not get from the websocket
      # (LoopWithIntervalObservable): the next read 3 s after the previous one ends.
      class Poller
        # @param appliance [Appliance]
        # @param klass [Class] a generated DOP2 class
        # @param address [Array<Integer>] where to read it
        # @param every [Numeric] seconds between the end of a read and the next
        # @param sleeper [#call] waits the given number of seconds
        def initialize(appliance, klass, address, every: 3, sleeper: method(:sleep))
          @appliance = appliance
          @klass = klass
          @address = address
          @every = every
          @sleeper = sleeper
        end

        # @yieldparam value [Data] the object, the first time and each time it changes
        # @return [Object] what +break+ returns
        # @api public
        def each
          previous = nil
          loop do
            value = @appliance.object(@klass, @address)
            yield value unless value == previous
            previous = value
            @sleeper.call(@every)
          end
        end
      end
    end
  end
end
