# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'

module Hl7Gateway
  # Sends the JSON document to the configured API and returns the parsed JSON answer.
  #
  # Failure modes are mapped to dedicated errors so the processor can pick the right HL7
  # acknowledgement code: 4xx -> UpstreamClientError (AE), everything else -> AR.
  class UpstreamClient
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, IOError, EOFError, SystemCallError, OpenSSL::SSL::SSLError
    ].freeze

    def initialize(config)
      @uri = config.upstream_url
      @token = config.upstream_token
      @timeout = config.upstream_timeout
    end

    def post(document)
      response = perform(build_request(document))
      handle(response)
    rescue *NETWORK_ERRORS => e
      raise UpstreamUnavailableError, "Upstream API unreachable (#{e.class})"
    end

    private

    def build_request(document)
      request = Net::HTTP::Post.new(@uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request['User-Agent'] = "hl7_gateway/#{VERSION}"
      request['X-HL7-Message-Type'] = document['message_type'] if document['message_type']
      request['X-HL7-Control-Id'] = document['control_id'] if document['control_id']
      request['Authorization'] = "Bearer #{@token}" if @token
      request.body = JSON.generate(document)
      request
    end

    def perform(request)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = @uri.scheme == 'https'
      http.open_timeout = http.read_timeout = http.write_timeout = @timeout
      http.request(request)
    end

    def handle(response)
      status = response.code.to_i

      case status
      when 200..299 then parse_success(response, status)
      when 400..499 then raise UpstreamClientError.new(error_text(response, status), status: status)
      else raise UpstreamUnavailableError.new("Upstream API answered HTTP #{status}", status: status)
      end
    end

    def parse_success(response, status)
      body = response.body.to_s.strip
      return {} if body.empty?

      parsed = JSON.parse(body)
      raise UpstreamResponseError.new('Upstream API must answer with a JSON object', status: status) unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise UpstreamResponseError.new('Upstream API answered with invalid JSON', status: status)
    end

    # Prefers the message the API itself provides ({"error": "..."} or {"message": "..."}).
    def error_text(response, status)
      parsed = JSON.parse(response.body.to_s)
      text = parsed['error'] || parsed['message'] if parsed.is_a?(Hash)
      text = text['message'] if text.is_a?(Hash)
      text.to_s.empty? ? "Upstream API rejected the request (HTTP #{status})" : text.to_s
    rescue JSON::ParserError
      "Upstream API rejected the request (HTTP #{status})"
    end
  end
end
