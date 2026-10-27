# frozen_string_literal: true

module Ajax
  module Sdk
    module Sia
      # One event the hub reported over SIA: its account, its two-letter SIA code and label, its group
      # (+ri+), the number after the code, its time, any text after that number, and the {Message} it came
      # in. As Ajax documents it, the number is the device for an alarm or a trouble, and the user (or the
      # device used) for arming and disarming. A content that does not read as SIA-DCS data keeps +code+
      # nil and lands whole in +text+.
      Event = Data.define(:account, :code, :label, :group, :number, :time, :text, :raw)

      # Reading an event out of a message.
      class Event
        CONTENT = %r{
          \A(?:\#\h+\|)?N?(?:ti\d\d:\d\d/)?(?:id\d*/)?(?:ri(?<group>\d*)/)?
          (?<code>[A-Z]{2})(?<number>\d*)(?<text>.*)\z
        }xm
        private_constant :CONTENT

        # @param message [Message]
        # @return [Event]
        def self.from(message)
          fields = CONTENT.match(message.content.to_s)&.named_captures || { 'text' => message.content }
          new(account: message.account, code: fields['code'], label: Codes.label(fields['code'].to_s),
              group: fields['group'], number: fields['number'], time: message.timestamp, text: fields['text'],
              raw: message)
        end
      end
    end
  end
end
