# frozen_string_literal: true

require 'uri'

module Hl7Gateway
  # Runtime configuration, read from environment variables.
  #
  #   UPSTREAM_API_URL          (required) endpoint that receives the JSON document
  #   UPSTREAM_API_TOKEN        optional bearer token sent to the upstream API
  #   UPSTREAM_API_TIMEOUT      seconds, applies to connect/read/write (default 10)
  #   HL7_HOST                  interface to bind (default 127.0.0.1)
  #   HL7_PORT                  MLLP listener port (default 2575)
  #   HL7_SENDING_APPLICATION   MSH-3 of every response (default HL7GATEWAY)
  #   HL7_SENDING_FACILITY      MSH-4 of every response (default HL7GATEWAY)
  #   HL7_IDLE_TIMEOUT          seconds before an idle connection is closed (default 60)
  #   HL7_MAX_MESSAGE_BYTES     upper bound for a single message (default 1048576)
  #   LOG_LEVEL                 debug, info, warn or error (default info)
  class Config
    LOG_LEVELS = %w[debug info warn error].freeze

    attr_reader :upstream_url, :upstream_token, :upstream_timeout, :host, :port,
                :sending_application, :sending_facility, :idle_timeout,
                :max_message_bytes, :log_level

    def self.from_env(env = ENV)
      new(
        upstream_url: env['UPSTREAM_API_URL'],
        upstream_token: blank_to_nil(env['UPSTREAM_API_TOKEN']),
        upstream_timeout: number(env, 'UPSTREAM_API_TIMEOUT', 10.0, :Float),
        host: env.fetch('HL7_HOST', '127.0.0.1'),
        port: number(env, 'HL7_PORT', 2575, :Integer),
        sending_application: env.fetch('HL7_SENDING_APPLICATION', 'HL7GATEWAY'),
        sending_facility: env.fetch('HL7_SENDING_FACILITY', 'HL7GATEWAY'),
        idle_timeout: number(env, 'HL7_IDLE_TIMEOUT', 60.0, :Float),
        max_message_bytes: number(env, 'HL7_MAX_MESSAGE_BYTES', 1_048_576, :Integer),
        log_level: env.fetch('LOG_LEVEL', 'info')
      )
    end

    def self.blank_to_nil(value)
      value.nil? || value.strip.empty? ? nil : value.strip
    end

    def self.number(env, key, default, kind)
      raw = blank_to_nil(env[key])
      return default unless raw

      Kernel.public_send(kind, raw)
    rescue ArgumentError
      raise ConfigError, "#{key} must be a valid #{kind == :Integer ? 'integer' : 'number'}, got #{raw.inspect}"
    end
    private_class_method :blank_to_nil, :number

    def initialize(upstream_url:, upstream_token: nil, upstream_timeout: 10.0, host: '127.0.0.1', port: 2575,
                   sending_application: 'HL7GATEWAY', sending_facility: 'HL7GATEWAY', idle_timeout: 60.0,
                   max_message_bytes: 1_048_576, log_level: 'info')
      @upstream_url = parse_url(upstream_url)
      @upstream_token = upstream_token
      @upstream_timeout = positive(upstream_timeout, 'UPSTREAM_API_TIMEOUT')
      @host = host
      @port = port_number(port)
      @sending_application = sending_application
      @sending_facility = sending_facility
      @idle_timeout = positive(idle_timeout, 'HL7_IDLE_TIMEOUT')
      @max_message_bytes = positive(max_message_bytes, 'HL7_MAX_MESSAGE_BYTES')
      @log_level = validate_log_level(log_level)
    end

    # Keeps the bearer token out of logs and stack traces.
    def inspect
      token = upstream_token ? '[REDACTED]' : 'nil'
      "#<#{self.class} upstream_url=#{upstream_url} upstream_token=#{token} host=#{host} port=#{port}>"
    end

    private

    def parse_url(value)
      raise ConfigError, 'UPSTREAM_API_URL is required' if value.nil? || value.strip.empty?

      uri = URI.parse(value.strip)
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
        raise ConfigError, "UPSTREAM_API_URL must be an http(s) URL, got #{value.inspect}"
      end

      uri
    rescue URI::InvalidURIError
      raise ConfigError, "UPSTREAM_API_URL is not a valid URL: #{value.inspect}"
    end

    def positive(value, name)
      raise ConfigError, "#{name} must be greater than zero" unless value.positive?

      value
    end

    def port_number(value)
      raise ConfigError, 'HL7_PORT must be between 0 and 65535' unless (0..65_535).cover?(value)

      value
    end

    def validate_log_level(value)
      level = value.to_s.downcase
      raise ConfigError, "LOG_LEVEL must be one of #{LOG_LEVELS.join(', ')}" unless LOG_LEVELS.include?(level)

      level
    end
  end
end
