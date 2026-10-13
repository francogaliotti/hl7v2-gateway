# frozen_string_literal: true

RSpec.describe Hl7Gateway::Processor do
  let(:config) { Hl7Gateway::Config.new(upstream_url: 'http://api.test/hl7', sending_application: 'GW') }
  let(:client) { instance_double(Hl7Gateway::UpstreamClient) }
  let(:log) { StringIO.new }
  let(:processor) { described_class.new(client: client, config: config, logger: Logger.new(log)) }
  let(:request) { hl7_fixture('oru_r01') }

  def response_for(payload)
    Hl7Gateway::Decoder.call(processor.call(payload))
  end

  def ack(response)
    Hl7Gateway::Document.fields(response, 'MSA')
  end

  describe 'a successful exchange' do
    before { allow(client).to receive(:post).and_return('message' => 'Stored', 'observations' => [{ 'identifier' => 'X', 'value' => 1 }]) }

    it 'sends the decoded message to the API' do
      processor.call(request)

      expect(client).to have_received(:post).with(a_hash_including('message_type' => 'ORU^R01', 'control_id' => 'MSG00042'))
    end

    it 'answers with HL7 built from the API response' do
      response = response_for(request)

      expect(response['message_type']).to eq('ORU^R01')
      expect(ack(response)).to include('acknowledgment_code' => 'AA', 'message_control_id' => 'MSG00042', 'text_message' => 'Stored')
      expect(Hl7Gateway::Document.fields(response, 'OBX')['observation_value']).to eq('1')
    end

    it 'terminates the answer with a carriage return' do
      expect(processor.call(request)).to end_with("\r")
    end

    it 'accepts MLLP framed input' do
      expect(ack(response_for(Hl7Gateway::MLLP.frame(request)))).to include('acknowledgment_code' => 'AA')
    end

    it 'logs the message type and control id but not the content' do
      processor.call(request)

      expect(log.string).to include('ORU^R01', 'MSG00042')
      expect(log.string).not_to include('ANDERSEN')
    end
  end

  describe 'failures are reported as negative acknowledgements' do
    it 'rejects malformed HL7 with AR and never calls the API' do
      allow(client).to receive(:post)

      response = response_for("MSH|^~\\&|CLINIC|SITE|||||ORM^O01|CTRL-9|P|2.5\rnot a segment")

      expect(ack(response)).to include('acknowledgment_code' => 'AR', 'message_control_id' => 'CTRL-9')
      expect(Hl7Gateway::Document.fields(response, 'ERR')['hl7_error_code']).to include('1' => '100')
      expect(client).not_to have_received(:post)
    end

    it 'rejects input without any MSH, even when nothing can be echoed' do
      response = response_for('hello')

      expect(ack(response)).to include('acknowledgment_code' => 'AR', 'message_control_id' => 'UNKNOWN')
    end

    it 'reports API validation errors with AE, passing the API text along' do
      allow(client).to receive(:post).and_raise(Hl7Gateway::UpstreamClientError.new('Weight is required', status: 422))

      response = response_for(request)

      expect(ack(response)).to include('acknowledgment_code' => 'AE', 'text_message' => 'Weight is required')
      expect(Hl7Gateway::Document.fields(response, 'ERR')).to include('application_error_code' => '422')
    end

    it 'reports an unavailable API with AR and a generic text' do
      allow(client).to receive(:post).and_raise(Hl7Gateway::UpstreamUnavailableError, 'Upstream API unreachable (Errno::ECONNREFUSED)')

      response = response_for(request)

      expect(ack(response)).to include('acknowledgment_code' => 'AR', 'text_message' => 'The request could not be processed right now')
      expect(log.string).to include('ECONNREFUSED')
    end

    it 'reports an unusable API answer with AR' do
      allow(client).to receive(:post).and_return('ack_code' => 'ZZ')

      expect(ack(response_for(request))).to include('acknowledgment_code' => 'AR')
    end

    it 'reports an API answer that cannot be encoded as HL7 with AR' do
      allow(client).to receive(:post).and_return('segments' => [{ 'segment' => 'PID', 'fields' => { 'shoe_size' => '42' } }])

      expect(ack(response_for(request))).to include('acknowledgment_code' => 'AR')
    end

    it 'does not leak internal error details' do
      allow(client).to receive(:post).and_raise(RuntimeError, 'secret stack detail')

      response = processor.call(request)

      expect(response).to include('AR', 'Internal gateway error')
      expect(response).not_to include('secret stack detail')
      expect(log.string).to include('secret stack detail')
    end
  end
end
