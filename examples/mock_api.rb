#!/usr/bin/env ruby
# frozen_string_literal: true

# A tiny stand-in for "your" API, so the gateway can be tried end to end without any
# real backend. It speaks the document format described in the README.
#
#   bundle exec ruby examples/mock_api.rb            # listens on :4567
#
#   * OBR-4 = BMI   -> computes the body mass index from the weight/height OBX segments
#   * ADT messages  -> acknowledged with a text
#   * anything else -> echoed back as "received"

require 'json'
require 'webrick'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hl7_gateway'

module MockApi
  WEIGHT_CODES = %w[29463-7 WEIGHT WT].freeze
  HEIGHT_CODES = %w[8302-2 HEIGHT HT].freeze
  BMI_CATEGORIES = [[18.5, 'Underweight'], [25.0, 'Normal'], [30.0, 'Overweight'], [Float::INFINITY, 'Obese']].freeze

  module_function

  # Takes the document received from the gateway, returns [http_status, json_body].
  def handle(document)
    return [200, { 'message' => 'Message received' }] unless document.is_a?(Hash)

    case service_id(document)
    when 'BMI' then bmi(document)
    else generic(document)
    end
  end

  def service_id(document)
    Hl7Gateway::Field.component(Hl7Gateway::Document.fields(document, 'OBR')['universal_service_identifier'])
  end

  def generic(document)
    text = document['message_type'].to_s.start_with?('ADT') ? 'Patient event recorded' : 'Message received'
    [200, { 'message' => text }]
  end

  def bmi(document)
    weight = measurement(document, WEIGHT_CODES, 'kg' => 1.0, 'lb' => 0.45359237)
    height = measurement(document, HEIGHT_CODES, 'cm' => 0.01, 'm' => 1.0, 'in' => 0.0254)
    return [422, { 'error' => 'Body weight and body height observations are required' }] unless weight && height

    bmi = (weight / (height**2)).round(1)
    [200, {
      'message' => 'BMI calculated',
      'observations' => [
        { 'identifier' => '39156-5', 'text' => 'Body mass index', 'coding_system' => 'LN',
          'value' => bmi, 'units' => 'kg/m2', 'reference_range' => '18.5-24.9',
          'abnormal_flags' => bmi.between?(18.5, 24.9) ? 'N' : 'A' },
        { 'identifier' => 'BMI-CAT', 'text' => 'BMI category', 'value' => category(bmi) }
      ]
    }]
  end

  # Value of the first matching OBX converted to SI (kg or m), or nil.
  def measurement(document, codes, factors)
    obx = Hl7Gateway::Document.segments(document, 'OBX').find do |segment|
      codes.include?(Hl7Gateway::Field.component(segment['fields']['observation_identifier']).to_s.upcase)
    end
    return nil unless obx

    fields = obx['fields']
    value = Float(fields['observation_value'], exception: false)
    factor = factors[Hl7Gateway::Field.component(fields['units']) || factors.keys.first]
    value && factor && (value * factor)
  end

  def category(bmi)
    BMI_CATEGORIES.find { |limit, _| bmi < limit }.last
  end

  # WEBrick adapter: POST /api/messages
  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(request, response) # rubocop:disable Naming/MethodName -- WEBrick dispatches on this name
      status, body = MockApi.handle(JSON.parse(request.body.to_s))
      response.status = status
      response['Content-Type'] = 'application/json'
      response.body = JSON.generate(body)
    rescue JSON::ParserError
      response.status = 400
      response['Content-Type'] = 'application/json'
      response.body = JSON.generate('error' => 'Body must be valid JSON')
    end
  end

  def server(port: 4567, logger: nil)
    options = { Port: port, BindAddress: '127.0.0.1' }
    options.merge!(Logger: logger, AccessLog: []) if logger
    WEBrick::HTTPServer.new(options).tap { |http| http.mount('/api/messages', Servlet) }
  end
end

if $PROGRAM_NAME == __FILE__
  http = MockApi.server(port: Integer(ENV.fetch('PORT', 4567)))
  trap('INT') { http.shutdown }
  trap('TERM') { http.shutdown }
  http.start
end
