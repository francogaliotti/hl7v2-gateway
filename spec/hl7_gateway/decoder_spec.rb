# frozen_string_literal: true

RSpec.describe Hl7Gateway::Decoder do
  describe '.call' do
    subject(:document) { described_class.call(hl7_fixture('oru_r01')) }

    def segments(name)
      Hl7Gateway::Document.segments(document, name)
    end

    it 'exposes the routing metadata of the message' do
      expect(document).to include('message_type' => 'ORU^R01', 'control_id' => 'MSG00042', 'version' => '2.5')
    end

    it 'keeps every segment, in order' do
      expect(document['segments'].map { |segment| segment['segment'] })
        .to eq(%w[MSH PID PV1 ORC OBR OBX OBX NTE NTE ZXT])
    end

    it 'names the fields of the MSH, including the separator characters' do
      expect(segments('MSH').first['fields']).to include(
        'field_separator' => '|', 'encoding_characters' => '^~\\&',
        'sending_application' => 'LABSYS', 'sending_facility' => 'CITY-LAB',
        'message_type' => { '1' => 'ORU', '2' => 'R01', '3' => 'ORU_R01' },
        'processing_id' => 'P', 'version_id' => '2.5', 'character_set' => 'UNICODE UTF-8'
      )
    end

    it 'parses composite and repeating fields' do
      pid = segments('PID').first['fields']

      expect(pid['patient_identifier_list']).to eq([
                                                     { '1' => 'MRN1001', '4' => 'MAIN-CAMPUS', '5' => 'MR' },
                                                     { '1' => 'NAT778', '4' => 'GOV', '5' => 'NI' }
                                                   ])
      expect(pid['patient_name']).to eq('1' => 'ANDERSEN', '2' => 'MARIE', '3' => 'L')
      expect(pid['home_phone']).to eq(%w[555-0101 555-0102])
    end

    it 'decodes escape sequences' do
      pid = segments('PID').first['fields']
      note = segments('OBX').last['fields']['observation_value']

      expect(pid['patient_address'].first['1']).to eq('12 Elm St&Co')
      expect(note).to eq("Sample slightly hemolysed\nRe-check advised")
    end

    it 'omits empty fields' do
      obr = segments('OBR').first['fields']

      expect(obr.keys).to eq(%w[set_id placer_order_number filler_order_number universal_service_identifier
                                observation_datetime])
    end

    it 'exposes unnamed fields and unknown segments positionally' do
      zxt = segments('ZXT').first['fields']

      expect(zxt).to eq('field_1' => 'custom', 'field_2' => { '1' => 'a', '2' => { '1' => 'b', '2' => 'c' } })
    end

    it 'keeps comments that follow an observation in message order' do
      notes = segments('NTE').map { |segment| segment['fields']['comment'] }

      expect(notes).to eq(['Reviewed by Dr. Okoye', 'Call back if value changes'])
    end

    it 'accepts a message with a different field and component separators' do
      doc = described_class.call(hl7_fixture('custom_delimiters'))

      expect(doc['message_type']).to eq('ORM^O01')
      expect(Hl7Gateway::Document.fields(doc, 'PID')['patient_name']).to eq('1' => 'SMITH', '2' => 'JOHN')
      expect(Hl7Gateway::Document.fields(doc, 'PID')['patient_identifier_list'])
        .to eq('1' => 'P1', '4' => 'HOSP', '5' => 'MR')
    end

    it 'tolerates MLLP wrapping, LF line endings and a missing final separator' do
      lf_message = hl7_fixture('adt_a01').tr("\r", "\n").chomp
      framed = "\x0B#{lf_message}\x1C\r"

      expect(described_class.call(framed)).to eq(described_class.call(hl7_fixture('adt_a01')))
    end

    it 'is JSON serialisable' do
      expect(JSON.parse(JSON.generate(document))).to eq(document)
    end

    it 'rejects text without an MSH' do
      expect { described_class.call("PID|1\rPV1|1") }.to raise_error(Hl7Gateway::ParseError, /MSH/)
    end

    it 'rejects lines that are not segments' do
      raw = "MSH|^~\\&|A|B||||ADT^A01|1|P|2.5\rthis is not a segment\r"

      expect { described_class.call(raw) }.to raise_error(Hl7Gateway::ParseError, /Line 2/)
    end

    it 'rejects an MSH with broken delimiters' do
      expect { described_class.call("MSH|\r") }.to raise_error(Hl7Gateway::ParseError)
    end

    it 'carries the HL7 error code reported to the sender' do
      expect { described_class.call('nothing') }
        .to raise_error(Hl7Gateway::ParseError) { |error| expect(error.hl7_error_code).to eq('100') }
    end
  end

  describe '.peek_header' do
    it 'recovers the MSH of a message that is broken further down' do
      raw = "MSH|^~\\&|CLINIC|SITE|||||ORM^O01|CTRL-9|P|2.5\rgarbage\r"

      header = Hl7Gateway::Document.fields(described_class.peek_header(raw), 'MSH')

      expect(header).to include('sending_application' => 'CLINIC', 'message_control_id' => 'CTRL-9')
    end

    it 'returns an empty document when nothing can be salvaged' do
      expect(described_class.peek_header('total nonsense')).to eq('segments' => [])
    end
  end
end
