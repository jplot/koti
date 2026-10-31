# frozen_string_literal: true

module Miele
  module Sdk
    # Requests of Dop1, the protocol hoods in +ProtocolVersion+ 2 answer at
    # +POST /Devices/{fab}/DOP/+: an object id, a request type, then the
    # object's packed section, as uppercase hex.
    module Dop1
      # Request type that reads an object.
      READ = '01'

      # Request type that writes an object.
      WRITE = '02'

      RUN_ON_TIMES = [0, 5, 15].freeze
      private_constant :RUN_ON_TIMES

      SETTING_VERSION = 1
      private_constant :SETTING_VERSION

      module_function

      # The app spells the object id in upper case and the section in lower case (Convert.ToString(b, 16)).
      #
      # @param object_id [String] four hex digits
      # @param type [String] {READ} or {WRITE}
      # @param section [String] packed section
      # @return [String]
      # @api public
      def request(object_id:, type:, section:) = "#{object_id}#{type}00#{section.unpack1('H*')}"

      # @param level [Integer] 0 (off) to 3, 4 (boost) or 5 (interval)
      # @return [String]
      # @raise [ArgumentError]
      # @api public
      def fan_level(level)
        raise ArgumentError, "fan level must be 0 to 5: #{level}" unless (0..5).cover?(level)

        request(object_id: '8E01', type: WRITE, section: [0, 0xFF, level, 0].pack('C4'))
      end

      # @param minutes [Integer] how long the fan keeps running once switched off
      # @return [String]
      # @raise [ArgumentError]
      # @api public
      def fan_run_on_time(minutes)
        raise ArgumentError, "run-on time must be 0, 5 or 15 minutes: #{minutes}" unless RUN_ON_TIMES.include?(minutes)

        request(object_id: '8E06', type: WRITE, section: [0, minutes].pack('C2'))
      end

      # @param on [Boolean]
      # @return [String]
      # @api public
      def main_light(on)
        section = [2, 1, on ? 4 : 0, 0, 0, 0, 0, 0, 0, on ? 0xFFFF : 0, 0].pack('C9n2')
        request(object_id: '1400', type: WRITE, section:)
      end

      # @param pf_id [Integer] programming function id (40010, 40011: the current grease and charcoal filter limits)
      # @return [String]
      # @raise [ArgumentError]
      # @api public
      def setting(pf_id)
        request(object_id: '1201', type: READ, section: [SETTING_VERSION, unsigned(pf_id, 16)].pack('Cn'))
      end

      # @param pf_id [Integer] programming function id
      # @param value [Integer] unsigned 32-bit value
      # @return [String]
      # @raise [ArgumentError]
      # @api public
      def write_setting(pf_id, value)
        section = [SETTING_VERSION, unsigned(pf_id, 16), unsigned(value, 32)].pack('CnN')
        request(object_id: '1201', type: WRITE, section:)
      end

      # The answer is the object id, the message type and the acknowledgement (8 hex digits), then the read
      # section: version (1 byte), programming function id (2), value (4), minimum (4) and maximum (4).
      #
      # @param response [String] hex of the +Response+ the hood answers
      # @return [Integer, nil] nil when the answer is too short to hold a value
      # @api public
      def setting_value(response)
        digits = response[14, 8].to_s
        digits.size == 8 ? digits.to_i(16) : nil
      end

      # @param value [Integer]
      # @param bits [Integer]
      # @return [Integer]
      # @raise [ArgumentError] if the value does not fit
      # @api private
      def unsigned(value, bits)
        raise ArgumentError, "#{value} does not fit in #{bits} unsigned bits" unless (0...(1 << bits)).cover?(value)

        value
      end
    end
  end
end
