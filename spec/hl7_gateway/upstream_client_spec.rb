# frozen_string_literal: true

RSpec.describe Hl7Gateway::UpstreamClient do
  let(:url) { 'http://api.test/v1/hl7/messages' }
  let(:token) { nil }
  let(:config) { Hl7Gateway::Config.new(upstream_url: url, upstream_token: token, upstream_timeout: 2) }
  let(:client) { described_class.new(config) }
  let(:document) { { 'message_type' => 'ORM^O01', 'control_id' => 'C1', 'segments' => [] } }

  def stub_api(**response)
    stub_request(:post, url).to_return(**response)
  end

  describe '#post' do
    it 'sends the document as JSON and returns the parsed answer' do
      stub = stub_request(:post, url)
             .with(body: document.to_json, headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' })
             .to_return(status: 200, body: '{"message":"ok"}')

      expect(client.post(document)).to eq('message' => 'ok')
      expect(stub).to have_been_requested
    end

    it 'identifies the message in request headers' do
      stub_api(status: 200, body: '{}')

      client.post(document)

      expect(WebMock).to have_requested(:post, url).with(headers: {
                                                           'X-Hl7-Message-Type' => 'ORM^O01', 'X-Hl7-Control-Id' => 'C1',
                                                           'User-Agent' => "hl7_gateway/#{Hl7Gateway::VERSION}"
                                                         })
    end

    context 'with a bearer token' do
      let(:token) { 'abc123' }

      it 'authenticates the request' do
        stub_api(status: 200, body: '{}')

        client.post(document)

        expect(WebMock).to have_requested(:post, url).with(headers: { 'Authorization' => 'Bearer abc123' })
      end
    end

    it 'does not send credentials when no token is configured' do
      stub_api(status: 200, body: '{}')

      client.post(document)

      expect(WebMock).not_to have_requested(:post, url).with(headers: { 'Authorization' => /.*/ })
    end

    it 'treats an empty successful body as an empty answer' do
      stub_api(status: 204, body: '')

      expect(client.post(document)).to eq({})
    end

    it 'posts to https endpoints' do
      secure = Hl7Gateway::Config.new(upstream_url: 'https://secure.test/hl7')
      stub = stub_request(:post, 'https://secure.test/hl7').to_return(status: 200, body: '{}')

      described_class.new(secure).post(document)

      expect(stub).to have_been_requested
    end

    it 'keeps the query string of the configured URL' do
      with_query = Hl7Gateway::Config.new(upstream_url: 'http://api.test/hl7?tenant=42')
      stub = stub_request(:post, 'http://api.test/hl7').with(query: { tenant: '42' }).to_return(status: 200, body: '{}')

      described_class.new(with_query).post(document)

      expect(stub).to have_been_requested
    end

    describe 'client errors' do
      it 'raises UpstreamClientError with the message sent by the API' do
        stub_api(status: 422, body: '{"error":"Weight is required"}')

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamClientError, 'Weight is required') do |error|
          expect(error.status).to eq(422)
        end
      end

      it 'also understands a "message" key and nested error objects' do
        stub_api(status: 400, body: '{"message":"Bad input"}')
        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamClientError, 'Bad input')

        stub_api(status: 400, body: '{"error":{"message":"Nested"}}')
        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamClientError, 'Nested')
      end

      it 'falls back to a generic text when the body is not JSON' do
        stub_api(status: 404, body: '<html>nope</html>')

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamClientError, /HTTP 404/)
      end
    end

    describe 'availability problems' do
      it 'raises UpstreamUnavailableError on 5xx' do
        stub_api(status: 503, body: 'down')

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamUnavailableError, /HTTP 503/)
      end

      it 'does not follow redirects' do
        stub_api(status: 302, headers: { 'Location' => 'http://elsewhere.test' })

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamUnavailableError, /HTTP 302/)
      end

      it 'raises UpstreamUnavailableError on timeouts' do
        stub_request(:post, url).to_timeout

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamUnavailableError, /unreachable/)
      end

      it 'raises UpstreamUnavailableError when the connection is refused' do
        stub_request(:post, url).to_raise(Errno::ECONNREFUSED)

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamUnavailableError)
      end

      it 'raises UpstreamUnavailableError when the host cannot be resolved' do
        stub_request(:post, url).to_raise(SocketError)

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamUnavailableError)
      end
    end

    describe 'unusable answers' do
      it 'rejects invalid JSON' do
        stub_api(status: 200, body: 'not json')

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamResponseError, /invalid JSON/)
      end

      it 'rejects JSON that is not an object' do
        stub_api(status: 200, body: '[1,2]')

        expect { client.post(document) }.to raise_error(Hl7Gateway::UpstreamResponseError, /JSON object/)
      end
    end
  end
end
