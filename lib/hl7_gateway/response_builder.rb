# frozen_string_literal: true

require 'securerandom'

module Hl7Gateway
  # Builds the JSON document of the HL7 response that goes back to the sender.
  #
  # Every response starts with MSH + MSA. What follows depends on the upstream answer:
  #
  #   {
  #     "ack_code": "AA",                       // AA (default), AE, AR, CA, CE or CR
  #     "message": "Free text for MSA-3",
  #     "message_type": "ORU^R01",              // default: ORU^R01 with observations, ACK^<event> without
  #     "observations": [                       // each one becomes an OBX segment
  #       { "identifier": "39156-5", "text": "BMI", "coding_system": "LN",
  #         "value": 24.7, "units": "kg/m2", "reference_range": "18.5-24.9",
  #         "abnormal_flags": "N", "value_type": "NM", "status": "F" }
  #     ],
  #     "segments": [ { "segment": "ZXT", "fields": { ... } } ]   // appended untouched
  #   }
  module ResponseBuilder
    ACK_CODES = %w[AA AE AR CA CE CR].freeze
    SUCCESS_CODES = %w[AA CA].freeze
    DEFAULT_VERSION = '2.5'
    ERROR_CODE_TABLE = 'HL70357'

    ERROR_DESCRIPTIONS = {
      '100' => 'Segment sequence error',
      '102' => 'Data type error',
      '207' => 'Application internal error'
    }.freeze

    module_function

    # Response for a request the upstream API processed.
    def from_upstream(request, body, config:)
      code = (body['ack_code'] || 'AA').to_s.upcase
      raise UpstreamResponseError, "Unsupported ack_code #{code.inspect}" unless ACK_CODES.include?(code)

      observations = Array(body['observations'])
      segments = [
        msh(request, config, message_type: response_type(request, body, observations)),
        msa(request, code, body['message'])
      ]
      segments << err(code, body['message']) unless SUCCESS_CODES.include?(code)
      segments.concat(result_segments(request, observations))
      segments.concat(extra_segments(body['segments']))

      document(segments)
    end

    # Negative acknowledgement. `request` may be a full document or just the best-effort
    # header returned by Decoder.peek_header.
    def error(request, config:, code:, text:, hl7_error_code: '207', application_error: nil)
      document([
                 msh(request, config, message_type: ack_type(request)),
                 msa(request, code, text),
                 err(code, text, hl7_error_code: hl7_error_code, application_error: application_error)
               ])
    end

    def document(segments)
      msh = segments.first['fields']
      {
        'message_type' => Decoder.message_type(msh['message_type']),
        'control_id' => msh['message_control_id'],
        'version' => msh['version_id'],
        'segments' => segments
      }
    end

    def msh(request, config, message_type:)
      incoming = Document.fields(request, 'MSH')
      {
        'segment' => 'MSH',
        'fields' => {
          'field_separator' => '|',
          'encoding_characters' => Delimiters::DEFAULT.encoding_characters,
          'sending_application' => config.sending_application,
          'sending_facility' => config.sending_facility,
          'receiving_application' => incoming['sending_application'],
          'receiving_facility' => incoming['sending_facility'],
          'message_datetime' => Time.now.strftime('%Y%m%d%H%M%S%z'),
          'message_type' => message_type,
          'message_control_id' => SecureRandom.hex(6).upcase,
          'processing_id' => incoming['processing_id'] || 'P',
          'version_id' => Field.component(incoming['version_id']) || DEFAULT_VERSION,
          'character_set' => 'UNICODE UTF-8'
        }.compact
      }
    end

    def msa(request, code, text)
      control_id = Field.component(Document.fields(request, 'MSH')['message_control_id']) || 'UNKNOWN'
      { 'segment' => 'MSA',
        'fields' => { 'acknowledgment_code' => code, 'message_control_id' => control_id,
                      'text_message' => text }.compact }
    end

    def err(code, text, hl7_error_code: '207', application_error: nil)
      fields = {
        'hl7_error_code' => { '1' => hl7_error_code, '2' => ERROR_DESCRIPTIONS.fetch(hl7_error_code, 'Error'),
                              '3' => ERROR_CODE_TABLE },
        'severity' => code.end_with?('A') ? 'W' : 'E',
        'application_error_code' => application_error,
        'user_message' => text
      }.compact
      { 'segment' => 'ERR', 'fields' => fields }
    end

    def response_type(request, body, observations)
      return Document.composite(body['message_type']) if body['message_type']

      observations.empty? ? ack_type(request) : { '1' => 'ORU', '2' => 'R01' }
    end

    def ack_type(request)
      event = Field.component(Document.fields(request, 'MSH')['message_type'], 2)
      { '1' => 'ACK', '2' => event }.compact
    end

    def result_segments(request, observations)
      return [] if observations.empty?

      pid = Document.segment(request, 'PID')
      obr = Document.fields(request, 'OBR')
      orc = Document.fields(request, 'ORC')

      segments = []
      segments << pid if pid
      segments << order_control(orc, obr) if orc.any? || obr.any?
      segments << order_request(orc, obr)
      observations.each_with_index { |observation, index| segments << obx(observation, index + 1) }
      segments
    end

    def order_control(orc, obr)
      { 'segment' => 'ORC',
        'fields' => {
          'order_control' => 'RE',
          'placer_order_number' => orc['placer_order_number'] || obr['placer_order_number'],
          'filler_order_number' => orc['filler_order_number'] || obr['filler_order_number'],
          'datetime_of_transaction' => Time.now.strftime('%Y%m%d%H%M%S')
        }.compact }
    end

    def order_request(orc, obr)
      { 'segment' => 'OBR',
        'fields' => {
          'set_id' => '1',
          'placer_order_number' => obr['placer_order_number'] || orc['placer_order_number'],
          'filler_order_number' => obr['filler_order_number'] || orc['filler_order_number'],
          'universal_service_identifier' => obr['universal_service_identifier'],
          'observation_datetime' => Time.now.strftime('%Y%m%d%H%M%S'),
          'result_status' => 'F'
        }.compact }
    end

    def obx(observation, set_id)
      raise UpstreamResponseError, 'Every observation must be an object' unless observation.is_a?(Hash)

      identifier = observation['identifier'] || observation['id']
      raise UpstreamResponseError, "Observation #{set_id} has no identifier" if identifier.to_s.empty?

      value = observation['value']
      { 'segment' => 'OBX',
        'fields' => {
          'set_id' => set_id.to_s,
          'value_type' => observation['value_type'] || (value.is_a?(Numeric) ? 'NM' : 'ST'),
          'observation_identifier' => { '1' => identifier, '2' => observation['text'],
                                        '3' => observation['coding_system'] }.compact,
          'observation_value' => format_value(value),
          'units' => observation['units'],
          'references_range' => observation['reference_range'],
          'abnormal_flags' => observation['abnormal_flags'],
          'observation_result_status' => observation['status'] || 'F'
        }.compact }
    end

    def extra_segments(segments)
      return [] if segments.nil?
      raise UpstreamResponseError, '"segments" must be an array' unless segments.is_a?(Array)

      segments
    end

    # HL7 numerics cannot use exponent notation, which Ruby falls back to for tiny/huge floats.
    def format_value(value)
      return value unless value.is_a?(Float)

      format('%.10f', value).sub(/0+\z/, '').sub(/\.\z/, '')
    end
  end
end
