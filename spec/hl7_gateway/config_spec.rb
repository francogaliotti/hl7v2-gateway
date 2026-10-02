# frozen_string_literal: true

RSpec.describe Hl7Gateway::Config do
  let(:env) { { 'UPSTREAM_API_URL' => 'http://localhost:4567/api/messages' } }

  describe '.from_env' do
    it 'reads the upstream endpoint from UPSTREAM_API_URL' do
      expect(described_class.from_env(env).upstream_url.to_s).to eq('http://localhost:4567/api/messages')
    end

    it 'applies sensible defaults' do
      config = described_class.from_env(env)

      expect(config).to have_attributes(
        host: '127.0.0.1', port: 2575, upstream_timeout: 10.0, upstream_token: nil,
        sending_application: 'HL7GATEWAY', sending_facility: 'HL7GATEWAY',
        idle_timeout: 60.0, max_message_bytes: 1_048_576, log_level: 'info'
      )
    end

    it 'reads every supported variable' do
      config = described_class.from_env(
        env.merge('UPSTREAM_API_TOKEN' => ' secret ', 'UPSTREAM_API_TIMEOUT' => '2.5', 'HL7_HOST' => '0.0.0.0',
                  'HL7_PORT' => '6000', 'HL7_SENDING_APPLICATION' => 'APP', 'HL7_SENDING_FACILITY' => 'FAC',
                  'HL7_IDLE_TIMEOUT' => '5', 'HL7_MAX_MESSAGE_BYTES' => '2048', 'LOG_LEVEL' => 'DEBUG')
      )

      expect(config).to have_attributes(
        upstream_token: 'secret', upstream_timeout: 2.5, host: '0.0.0.0', port: 6000,
        sending_application: 'APP', sending_facility: 'FAC', idle_timeout: 5.0,
        max_message_bytes: 2048, log_level: 'debug'
      )
    end

    it 'treats blank optional variables as unset' do
      config = described_class.from_env(env.merge('UPSTREAM_API_TOKEN' => '  ', 'HL7_PORT' => ''))

      expect(config).to have_attributes(upstream_token: nil, port: 2575)
    end

    it 'supports https endpoints' do
      config = described_class.from_env('UPSTREAM_API_URL' => 'https://api.example.com/v1/hl7')

      expect(config.upstream_url.scheme).to eq('https')
    end
  end

  describe 'validation' do
    it 'requires UPSTREAM_API_URL' do
      expect { described_class.from_env({}) }.to raise_error(Hl7Gateway::ConfigError, /UPSTREAM_API_URL is required/)
    end

    it 'rejects URLs that are not http(s)' do
      expect { described_class.from_env('UPSTREAM_API_URL' => 'ftp://example.com') }
        .to raise_error(Hl7Gateway::ConfigError, /http\(s\) URL/)
    end

    it 'rejects unparseable URLs' do
      expect { described_class.from_env('UPSTREAM_API_URL' => 'http://bad host') }
        .to raise_error(Hl7Gateway::ConfigError, /not a valid URL/)
    end

    it 'rejects non numeric values' do
      expect { described_class.from_env(env.merge('HL7_PORT' => 'abc')) }
        .to raise_error(Hl7Gateway::ConfigError, /HL7_PORT must be a valid integer/)
    end

    it 'rejects out of range ports' do
      expect { described_class.from_env(env.merge('HL7_PORT' => '70000')) }
        .to raise_error(Hl7Gateway::ConfigError, /HL7_PORT/)
    end

    it 'rejects non positive timeouts' do
      expect { described_class.from_env(env.merge('UPSTREAM_API_TIMEOUT' => '0')) }
        .to raise_error(Hl7Gateway::ConfigError, /UPSTREAM_API_TIMEOUT/)
    end

    it 'rejects unknown log levels' do
      expect { described_class.from_env(env.merge('LOG_LEVEL' => 'loud')) }
        .to raise_error(Hl7Gateway::ConfigError, /LOG_LEVEL/)
    end
  end

  describe '#inspect' do
    it 'never prints the bearer token' do
      config = described_class.from_env(env.merge('UPSTREAM_API_TOKEN' => 'super-secret'))

      expect(config.inspect).not_to include('super-secret')
      expect(config.inspect).to include('[REDACTED]')
    end
  end
end
