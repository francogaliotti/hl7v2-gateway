# frozen_string_literal: true

require 'logger'

module Hl7Gateway
  # The whole pipeline for one message: HL7 in, HL7 out.
  #
  #   raw HL7 -> Decoder -> JSON document -> UpstreamClient -> JSON answer -> ResponseBuilder -> Encoder -> HL7
  #
  # `call` never raises: whatever goes wrong is reported to the sender as a negative
  # acknowledgement, so a faulty message can never kill the connection.
  #
  #   malformed HL7                     -> AR (reject), ERR 100
  #   upstream 4xx                      -> AE (application error), text taken from the API
  #   upstream down / timeout / 5xx     -> AR, ERR 207
  #   anything unexpected               -> AR, ERR 207
  class Processor
    def initialize(client:, config:, logger: Logger.new(nil))
      @client = client
      @config = config
      @logger = logger
    end

    def call(payload)
      request = Decoder.call(payload)
      @logger.info("Received #{request['message_type'] || 'unknown'} control_id=#{request['control_id']}")

      body = @client.post(request)
      Encoder.call(ResponseBuilder.from_upstream(request, body, config: @config))
    rescue ParseError => e
      reject(payload, 'AR', e.message, hl7_error_code: e.hl7_error_code)
    rescue UpstreamClientError => e
      reject(request, 'AE', e.message, application_error: e.status.to_s)
    rescue UpstreamError, EncodeError => e
      @logger.error("Cannot complete request: #{e.class}: #{e.message}")
      reject(request, 'AR', 'The request could not be processed right now')
    rescue StandardError => e
      @logger.error("Unexpected failure: #{e.class}: #{e.message}")
      reject(request, 'AR', 'Internal gateway error')
    end

    private

    def reject(request, code, text, hl7_error_code: '207', application_error: nil)
      @logger.warn("Responding #{code}: #{text}")
      addressed_to = request.is_a?(Hash) ? request : Decoder.peek_header(request)
      Encoder.call(
        ResponseBuilder.error(addressed_to, config: @config, code: code, text: text,
                                            hl7_error_code: hl7_error_code, application_error: application_error)
      )
    end
  end
end
