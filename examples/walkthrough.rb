#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs one HL7 message through every stage of the gateway and prints what comes out of each.
# It starts the example API on a free port, so nothing else needs to be running.
#
#   bundle exec ruby examples/walkthrough.rb [path/to/message.hl7]

require 'json'
require 'logger'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hl7_gateway'
require_relative 'mock_api'

def stage(number, title)
  puts "\n#{'=' * 78}\n#{number}. #{title}\n#{'=' * 78}"
end

def show_hl7(text)
  puts text.tr("\r", "\n")
end

path = ARGV.first || File.expand_path('messages/bmi_request.hl7', __dir__)
raw = File.binread(path)

api = MockApi.server(port: 0, logger: WEBrick::Log.new(File::NULL))
api_thread = Thread.new { api.start }
url = "http://127.0.0.1:#{api.listeners.first.addr[1]}/api/messages"
config = Hl7Gateway::Config.new(upstream_url: url, sending_application: 'HL7GATEWAY', sending_facility: 'DEMO')

body = nil
begin
  stage(1, 'Bytes received on the socket (shown with MLLP framing escaped)')
  framed = Hl7Gateway::MLLP.frame(raw.gsub(/\r?\n/, "\r"))
  puts framed.inspect

  stage(2, 'After MLLP unframing + Sanitizer (UTF-8, one <CR> per segment)')
  payload = Hl7Gateway::MLLP.unframe(framed)
  clean = Hl7Gateway::Sanitizer.call(payload)
  show_hl7(clean)

  stage(3, "Decoder: HL7 -> JSON document (what the API receives via POST #{url})")
  request = Hl7Gateway::Decoder.call(clean)
  puts JSON.pretty_generate(request)

  stage(4, 'Raw JSON answer from the upstream API')
  body = Hl7Gateway::UpstreamClient.new(config).post(request)
  puts JSON.pretty_generate(body)
rescue Hl7Gateway::UpstreamClientError => e
  puts "The API rejected the request (HTTP #{e.status}): #{e.message}"
end

if body
  stage(5, 'ResponseBuilder: API answer -> HL7 response document (JSON)')
  response = Hl7Gateway::ResponseBuilder.from_upstream(request, body, config: config)
  puts JSON.pretty_generate(response)

  stage(6, 'Encoder: response document -> final HL7 text')
  hl7 = Hl7Gateway::Encoder.call(response)
  show_hl7(hl7)

  stage(7, 'Bytes written back to the socket')
  puts Hl7Gateway::MLLP.frame(hl7).inspect
end

api.shutdown
api_thread.join(2)
