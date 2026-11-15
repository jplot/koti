# frozen_string_literal: true

module Miele
  module Sdk
    # The Dop1 requests of an {Appliance}.
    module Dop1Access
      # Sends a Dop1 request, which hoods in +ProtocolVersion+ 2 answer instead of DOP2.
      #
      # @param request [String] built by {Dop1}
      # @param timeout [Numeric, nil] as {Connection.request} takes it
      # @return [String] the hood's answer: +{"Response": hex}+ to a read
      # @api public
      def dop1(request, timeout: nil)
        send_request(:post, "/Devices/#{fab}/DOP/", body: JSON.generate(Request: request), timeout:).body
      end

      private

      # @param klass [Class] a generated Dop1 write section
      # @return [Data] all its bytes 0, as the app allocates it
      def blank(klass) = klass.from("\0" * klass::LENGTH)

      # @param klass [Class] a generated Dop1 object
      # @param section [Data] one of its write sections
      # @param type [String] {Dop1::READ} or {Dop1::WRITE}, as the app sends that object
      # @param timeout [Numeric, nil]
      # @return [void]
      # @raise [NotAcceptedError] for an Ack other than 1
      def write_dop1_object(klass, section, type:, timeout: nil)
        write_dop1(Dop1.request(object_id: klass::ID, type:, section: section.to_bytes), timeout:)
      end

      # The app accepts only Ack 1, characters 6 and 7 of the answer.
      #
      # @param request [String] built by {Dop1}
      # @param timeout [Numeric, nil]
      # @return [void]
      # @raise [NotAcceptedError] for any other Ack, or an answer without one
      def write_dop1(request, timeout: nil)
        answer = dop1(request, timeout:)
        ack = Dop1.ack(answer)
        raise NotAcceptedError, "the appliance answered #{answer.inspect}" if ack.nil?
        raise NotAcceptedError, "the appliance answered Ack #{ack.inspect}" unless ack.to_i == 1
      end

      # @param klass [Class] a generated Dop1 object
      # @param timeout [Numeric, nil]
      # @return [Data] read with an empty section, as the app reads its laundry and dishwasher objects
      # @raise [NotAcceptedError] for an answer without a +Response+ that carries the object
      def dop1_object(klass, timeout: nil)
        request = Dop1.request(object_id: klass::ID, type: Dop1::READ, section: '')
        answer = dop1(request, timeout:)
        response = Dop1.response(answer).to_s
        raise NotAcceptedError, "the appliance answered #{answer.inspect}" if response.size < 8

        klass.from([response[8..]].pack('H*'))
      end
    end
  end
end
