# frozen_string_literal: true

module Hl7Gateway
  # Base class for every error raised by this library.
  class Error < StandardError; end

  # Invalid or missing environment configuration.
  class ConfigError < Error; end

  # The byte stream does not follow the MLLP framing rules.
  class FramingError < Error; end

  # The inbound payload is not a valid HL7 v2 message.
  class ParseError < Error
    # HL7 table 0357 code reported back to the sender in the ERR segment.
    attr_reader :hl7_error_code

    def initialize(message = 'Invalid HL7 message', hl7_error_code: '100')
      super(message)
      @hl7_error_code = hl7_error_code
    end
  end

  # A JSON document cannot be turned into an HL7 message.
  class EncodeError < Error; end

  # Something went wrong while talking to the upstream API.
  class UpstreamError < Error
    attr_reader :status

    def initialize(message = 'Upstream API error', status: nil)
      super(message)
      @status = status
    end
  end

  # The upstream API answered with a 4xx: it understood us and refused the content.
  class UpstreamClientError < UpstreamError; end

  # The upstream API could not be reached, timed out or answered with a 5xx.
  class UpstreamUnavailableError < UpstreamError; end

  # The upstream API answered 2xx but the body cannot be used.
  class UpstreamResponseError < UpstreamError; end
end
