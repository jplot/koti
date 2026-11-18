# frozen_string_literal: true

require 'open3'

RSpec.describe Koti::Application do
  context 'when RAILS_ENV is production' do
    def tls_settings(env)
      script = 'print [Rails.application.config.force_ssl, Rails.application.config.assume_ssl].inspect'
      output, status = Open3.capture2e({ 'RAILS_ENV' => 'production', 'SECRET_KEY_BASE' => 'x' * 64 }.merge(env),
                                       'bin/rails', 'runner', script, chdir: Rails.root.to_s)
      raise output unless status.success?

      output.lines.last
    end

    it 'serves plain HTTP on the LAN, where a Secure cookie would be dropped' do
      expect(tls_settings({})).to eq('[false, false]')
    end

    it 'forces TLS behind a TLS proxy' do
      expect(tls_settings('KOTI_TLS' => '1')).to eq('[true, true]')
    end
  end
end
