# frozen_string_literal: true

RSpec.describe Hl7Gateway::ResponseBuilder do
  let(:config) do
    Hl7Gateway::Config.new(upstream_url: 'http://api.test/hl7', sending_application: 'GW', sending_facility: 'GWF')
  end
  let(:request) { Hl7Gateway::Decoder.call(hl7_fixture('oru_r01')) }

  def segments(document, name)
    Hl7Gateway::Document.segments(document, name)
  end

  def fields(document, name)
    Hl7Gateway::Document.fields(document, name)
  end

  describe '.from_upstream' do
    context 'when the API only sends a text' do
      subject(:response) { described_class.from_upstream(request, { 'message' => 'All good' }, config: config) }

      it 'acknowledges the request with MSH + MSA' do
        expect(response['segments'].map { |segment| segment['segment'] }).to eq(%w[MSH MSA])
        expect(fields(response, 'MSA')).to eq(
          'acknowledgment_code' => 'AA', 'message_control_id' => 'MSG00042', 'text_message' => 'All good'
        )
      end

      it 'answers with an ACK for the trigger event of the request' do
        expect(response['message_type']).to eq('ACK^R01')
      end

      it 'addresses the original sender' do
        expect(fields(response, 'MSH')).to include(
          'sending_application' => 'GW', 'sending_facility' => 'GWF',
          'receiving_application' => 'LABSYS', 'receiving_facility' => 'CITY-LAB',
          'version_id' => '2.5', 'processing_id' => 'P', 'character_set' => 'UNICODE UTF-8'
        )
      end

      it 'generates a fresh control id and timestamp' do
        header = fields(response, 'MSH')

        expect(header['message_control_id']).to match(/\A\h{12}\z/).and(satisfy { |id| id != 'MSG00042' })
        expect(header['message_datetime']).to match(/\A\d{14}[+-]\d{4}\z/)
      end
    end

    context 'when the API sends observations' do
      subject(:response) do
        described_class.from_upstream(request, {
                                        'observations' => [
                                          { 'identifier' => '39156-5', 'text' => 'BMI', 'coding_system' => 'LN',
                                            'value' => 24.7, 'units' => 'kg/m2', 'reference_range' => '18.5-24.9',
                                            'abnormal_flags' => 'N' },
                                          { 'identifier' => 'CAT', 'value' => 'Normal' },
                                          { 'identifier' => 'COUNT', 'value' => 3, 'status' => 'C' },
                                          { 'identifier' => 'TINY', 'value' => 0.00001234 }
                                        ]
                                      }, config: config)
      end

      it 'replies with an ORU^R01 carrying the patient, order and results' do
        expect(response['message_type']).to eq('ORU^R01')
        expect(response['segments'].map { |segment| segment['segment'] }).to eq(%w[MSH MSA PID ORC OBR OBX OBX OBX OBX])
      end

      it 'echoes the patient and order identifiers' do
        expect(segments(response, 'PID').first).to eq(segments(request, 'PID').first)
        expect(fields(response, 'ORC')).to include('order_control' => 'RE', 'placer_order_number' => 'ORD-77',
                                                   'filler_order_number' => 'FILL-88')
        expect(fields(response, 'OBR')).to include(
          'set_id' => '1', 'placer_order_number' => 'ORD-77', 'result_status' => 'F',
          'universal_service_identifier' => { '1' => 'CBC', '2' => 'Complete blood count', '3' => 'LOCAL' }
        )
      end

      it 'turns each observation into an OBX' do
        bmi, category, count, tiny = segments(response, 'OBX').map { |segment| segment['fields'] }

        expect(bmi).to eq(
          'set_id' => '1', 'value_type' => 'NM',
          'observation_identifier' => { '1' => '39156-5', '2' => 'BMI', '3' => 'LN' },
          'observation_value' => '24.7', 'units' => 'kg/m2', 'references_range' => '18.5-24.9',
          'abnormal_flags' => 'N', 'observation_result_status' => 'F'
        )
        expect(category).to include('value_type' => 'ST', 'observation_value' => 'Normal')
        expect(count).to include('value_type' => 'NM', 'observation_result_status' => 'C')
        expect(tiny['observation_value']).to eq('0.00001234')
      end

      it 'produces a valid HL7 message' do
        text = Hl7Gateway::Encoder.call(response)

        expect(text).to include("OBX|1|NM|39156-5^BMI^LN||24.7|kg/m2|18.5-24.9|N|||F\r")
        expect(text).to include("OBX|3|NM|COUNT||3||||||C\r")
      end
    end

    context 'without an order in the request' do
      it 'still builds the OBR needed by the results' do
        plain = Hl7Gateway::Decoder.call(hl7('MSH|^~\\&|A|B|C|D|20261001||ADT^A01|7|P|2.4'))
        response = described_class.from_upstream(plain, { 'observations' => [{ 'identifier' => 'X', 'value' => 1 }] }, config: config)

        expect(response['segments'].map { |segment| segment['segment'] }).to eq(%w[MSH MSA OBR OBX])
        expect(fields(response, 'MSH')['version_id']).to eq('2.4')
      end
    end

    it 'lets the API choose the response type' do
      response = described_class.from_upstream(request, { 'message_type' => 'RSP^K11' }, config: config)

      expect(response['message_type']).to eq('RSP^K11')
    end

    it 'appends extra segments untouched' do
      extra = { 'segment' => 'ZXT', 'fields' => { 'field_1' => 'custom' } }

      response = described_class.from_upstream(request, { 'segments' => [extra] }, config: config)

      expect(response['segments'].last).to eq(extra)
    end

    it 'adds an ERR segment when the API reports an application error' do
      response = described_class.from_upstream(request, { 'ack_code' => 'ae', 'message' => 'Unknown patient' }, config: config)

      expect(fields(response, 'MSA')).to include('acknowledgment_code' => 'AE', 'text_message' => 'Unknown patient')
      expect(fields(response, 'ERR')).to include('severity' => 'E', 'user_message' => 'Unknown patient')
    end

    it 'does not add an ERR segment for commit acknowledgements' do
      response = described_class.from_upstream(request, { 'ack_code' => 'CA' }, config: config)

      expect(segments(response, 'ERR')).to be_empty
    end

    it 'rejects unsupported ack codes' do
      expect { described_class.from_upstream(request, { 'ack_code' => 'XX' }, config: config) }
        .to raise_error(Hl7Gateway::UpstreamResponseError, /ack_code/)
    end

    it 'rejects observations without an identifier' do
      expect { described_class.from_upstream(request, { 'observations' => [{ 'value' => 1 }] }, config: config) }
        .to raise_error(Hl7Gateway::UpstreamResponseError, /no identifier/)
    end

    it 'rejects observations that are not objects' do
      expect { described_class.from_upstream(request, { 'observations' => ['x'] }, config: config) }
        .to raise_error(Hl7Gateway::UpstreamResponseError)
    end

    it 'rejects extra segments that are not a list' do
      expect { described_class.from_upstream(request, { 'segments' => {} }, config: config) }
        .to raise_error(Hl7Gateway::UpstreamResponseError, /array/)
    end
  end

  describe '.error' do
    it 'builds a negative acknowledgement with an ERR segment' do
      response = described_class.error(request, config: config, code: 'AR', text: 'Try later',
                                                hl7_error_code: '207', application_error: '503')

      expect(response['segments'].map { |segment| segment['segment'] }).to eq(%w[MSH MSA ERR])
      expect(fields(response, 'MSA')).to include('acknowledgment_code' => 'AR', 'message_control_id' => 'MSG00042')
      expect(fields(response, 'ERR')).to eq(
        'hl7_error_code' => { '1' => '207', '2' => 'Application internal error', '3' => 'HL70357' },
        'severity' => 'E', 'application_error_code' => '503', 'user_message' => 'Try later'
      )
    end

    it 'still works when nothing is known about the request' do
      response = described_class.error({ 'segments' => [] }, config: config, code: 'AR', text: 'Garbled')

      expect(fields(response, 'MSA')['message_control_id']).to eq('UNKNOWN')
      expect(response['message_type']).to eq('ACK')
      expect(fields(response, 'MSH')['version_id']).to eq('2.5')
    end
  end
end
