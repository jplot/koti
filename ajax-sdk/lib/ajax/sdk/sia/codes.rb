# frozen_string_literal: true

module Ajax
  module Sdk
    module Sia
      # The SIA event codes and their English labels, from pysiaalarm's table (MIT License, see LICENSE).
      module Codes
        LABELS = File.readlines(File.join(__dir__ || '.', 'codes.tsv'), chomp: true, encoding: 'UTF-8')
                     .to_h { [it[0, 2].to_s, it[3..].to_s] }.freeze
        private_constant :LABELS

        # @param code [String] a two-letter SIA code, such as +"BA"+
        # @return [String, nil] its label, such as +"Burglary Alarm"+
        def self.label(code) = LABELS[code]
      end
    end
  end
end
