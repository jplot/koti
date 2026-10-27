# frozen_string_literal: true

require 'time'

module Ajax
  module Sdk
    module Sia
      # One DC-09 frame from the hub: its type (+"SIA-DCS"+, +"ADM-CID"+ or +"NULL"+), whether it was
      # encrypted, its sequence, receiver, line and account, its content between the brackets, and its
      # timestamp (UTC) when it carries one.
      Message = Data.define(:type, :encrypted, :sequence, :receiver, :line, :account, :content, :timestamp)

      # Parsing frames and building the answers the hub expects.
      class Message
        FRAME = /
          \A\n?(?<crc>\h{4})(?<length>\h{4})
          (?<body>"(?<star>\*)?(?<type>SIA-DCS|ADM-CID|NULL)"(?<sequence>\d{4})
          (?<receiver>R\h{1,6})?(?<line>L\h{1,6})\#(?<account>\h{3,16})\[(?<rest>[^\r]*))\r?\z
        /x
        STAMP = /_\d\d:\d\d:\d\d,\d\d-\d\d-\d{4}\z/
        private_constant :FRAME, :STAMP

        # @param frame [String] the bytes from the +\n+ to the +\r+
        # @param cipher [Cipher, nil] opens an encrypted frame; without it, only its header is read
        # @return [Message]
        # @raise [FrameError] on a wrong CRC or length, an unreadable frame, or one the cipher does not open
        def self.parse(frame, cipher: nil)
          match = FRAME.match(frame.b) or raise FrameError, 'not a DC-09 frame'
          check(match)
          build(match, match[:star] ? cipher && unseal(match[:rest], cipher, match[:type]) : clear(match[:rest]))
        end

        # @param time [Time]
        # @return [String] the NAK frame, in clear, carrying the receiver's time so the hub can resynchronise
        def self.nak(time = Time.now) = frame(%("NAK"0000R0L0A0[]#{stamp(time)}))

        # @api private
        # @return [String] +body+ framed with its CRC and length
        def self.frame(body)
          format("\n%<crc>04X%<length>04X%<body>s\r", crc: Sia.crc(body), length: body.bytesize, body:)
        end

        # @api private
        # @return [String] +time+ as DC-09 writes it
        def self.stamp(time) = time.getutc.strftime('_%H:%M:%S,%m-%d-%Y')

        def self.check(match)
          raise FrameError, 'CRC mismatch' unless match[:crc].hex == Sia.crc(match[:body])
          raise FrameError, 'length mismatch' unless match[:length].hex == match[:body].bytesize
        end

        def self.build(match, plain)
          new(type: match[:type], encrypted: !match[:star].nil?, sequence: match[:sequence], receiver: match[:receiver],
              line: match[:line], account: match[:account], content: plain && content_of(plain),
              timestamp: plain && time_in(plain))
        end

        def self.content_of(plain) = plain.partition(']').first.force_encoding('UTF-8').scrub

        # Encrypted frames must end with a timestamp, which noise from a wrong key never does. Only a link
        # test may lack the pipe after its padding, so a replayed ACK cannot pass for an event.
        def self.unseal(hex, cipher, type)
          raise FrameError, 'encrypted part is not whole AES blocks' unless hex.match?(/\A(?:\h{32})+\z/)

          plain = cipher.decrypt(hex)
          plain = if plain.include?('|') then plain.split('|', 2).fetch(1)
                  elsif type == 'NULL' then plain[/\].*\z/m].to_s
                  else raise FrameError, 'no pipe after the padding of a data frame'
                  end
          plain.match?(STAMP) ? plain : raise(FrameError, 'the key does not open this frame')
        end

        def self.clear(rest) = rest.include?(']') ? rest : raise(FrameError, 'no closing bracket')

        def self.time_in(plain)
          text = plain[STAMP] or return
          Time.strptime("#{text} +0000", '_%H:%M:%S,%m-%d-%Y %z').utc
        rescue ArgumentError
          raise FrameError, 'unreadable timestamp'
        end
        private_class_method :check, :build, :content_of, :unseal, :clear, :time_in

        # @param cipher [Cipher, nil] encrypts the answer to an encrypted frame
        # @return [String] the ACK frame, encrypted when the frame was
        def ack(cipher: nil) = answer('ACK', encrypted ? cipher : nil)

        # @return [String] the DUH frame (unknown account or refused frame), in clear
        def duh = answer('DUH', nil)

        private

        def answer(kind, cipher)
          head = "#{sequence}#{receiver}#{line}##{account}["
          return Message.frame(%("#{kind}"#{head}])) unless cipher

          Message.frame(%("*#{kind}"#{head}#{cipher.encrypt("]#{Message.stamp(Time.now)}")}))
        end
      end
    end
  end
end
