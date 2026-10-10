# frozen_string_literal: true

RSpec.describe Hl7Gateway::Encoder do
  def doc(*segments)
    { 'segments' => segments }
  end

  def seg(name, fields = {})
    { 'segment' => name, 'fields' => fields }
  end

  let(:msh) { seg('MSH', 'sending_application' => 'APP', 'message_type' => { '1' => 'ACK', '2' => 'A01' }) }

  describe '.call' do
    it 'builds an MSH with default delimiters and ends every segment with <CR>' do
      expect(described_class.call(doc(msh))).to eq("MSH|^~\\&|APP||||||ACK^A01\r")
    end

    it 'places named fields at their HL7 position' do
      message = described_class.call(doc(msh, seg('PID', 'set_id' => '1', 'patient_name' => { '1' => 'DOE', '2' => 'JANE' },
                                                         'administrative_sex' => 'F')))

      expect(message.split("\r").last).to eq('PID|1||||DOE^JANE|||F')
    end

    it 'accepts field_<n> keys and bare numbers' do
      message = described_class.call(doc(msh, seg('ZAB', 'field_2' => 'two', '4' => 'four')))

      expect(message.split("\r").last).to eq('ZAB||two||four')
    end

    it 'escapes delimiters found in data' do
      message = described_class.call(doc(msh, seg('NTE', 'comment' => "AT&T | 50%\nsecond line")))

      expect(message.split("\r").last).to eq('NTE|||AT\\T\\T \\F\\ 50%\\.br\\second line')
    end

    it 'serialises numbers and repetitions' do
      message = described_class.call(doc(msh, seg('OBX', 'observation_value' => 23.5, 'units' => %w[a b])))

      expect(message.split("\r").last).to eq('OBX|||||23.5|a~b')
    end

    it 'numbers consecutive repeating segments' do
      message = described_class.call(doc(msh, seg('OBX'), seg('OBX')))

      expect(message.split("\r").last(2).map { |line| line[/\AOBX\|(\d+)/, 1] }).to eq(%w[1 2])
    end

    it 'uses the delimiters declared in the MSH' do
      header = seg('MSH', 'field_separator' => '#', 'encoding_characters' => '$*\\@', 'message_type' => { '1' => 'ORM', '2' => 'O01' })
      message = described_class.call(doc(header, seg('PID', 'patient_name' => { '1' => 'A', '2' => 'B' })))

      expect(message.split("\r")).to eq(['MSH#$*\\@#######ORM$O01', 'PID#####A$B'])
    end

    it 'can be read back by ruby-hl7' do
      message = described_class.call(doc(msh, seg('PID', 'set_id' => '1'), seg('ZZZ', 'field_1' => 'x')))

      parsed = HL7::Message.new(message.chomp("\r"))
      expect(parsed.map { |segment| segment[0] }).to eq(%w[MSH PID ZZZ])
    end
  end

  describe 'validation' do
    it 'needs at least one segment' do
      expect { described_class.call({}) }.to raise_error(Hl7Gateway::EncodeError, /no segments/)
      expect { described_class.call('segments' => []) }.to raise_error(Hl7Gateway::EncodeError)
    end

    it 'needs the MSH first' do
      expect { described_class.call(doc(seg('PID'))) }.to raise_error(Hl7Gateway::EncodeError, /MSH/)
    end

    it 'rejects invalid segment ids' do
      expect { described_class.call(doc(msh, seg('pid!'))) }.to raise_error(Hl7Gateway::EncodeError, /Invalid segment id/)
      expect { described_class.call(doc(msh, 'fields' => {})) }.to raise_error(Hl7Gateway::EncodeError, /Invalid segment id/)
    end

    it 'rejects segments that are not objects' do
      expect { described_class.call(doc(msh, 'PID|1')) }.to raise_error(Hl7Gateway::EncodeError, /object/)
    end

    it 'rejects fields that are not an object' do
      expect { described_class.call(doc(msh, 'segment' => 'PID', 'fields' => [])) }
        .to raise_error(Hl7Gateway::EncodeError, /must be an object/)
    end

    it 'rejects unknown field names' do
      expect { described_class.call(doc(msh, seg('PID', 'shoe_size' => '42'))) }
        .to raise_error(Hl7Gateway::EncodeError, /Unknown field/)
    end

    it 'rejects an invalid field separator' do
      header = seg('MSH', 'field_separator' => '||')

      expect { described_class.call(doc(header)) }.to raise_error(Hl7Gateway::EncodeError, /single character/)
    end

    it 'rejects invalid encoding characters' do
      header = seg('MSH', 'encoding_characters' => '^^')

      expect { described_class.call(doc(header)) }.to raise_error(Hl7Gateway::EncodeError)
    end
  end
end
