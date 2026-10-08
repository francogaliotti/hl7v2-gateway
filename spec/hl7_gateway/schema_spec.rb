# frozen_string_literal: true

RSpec.describe Hl7Gateway::Schema do
  describe '.field_name' do
    it 'names the fields of known segments' do
      expect(described_class.field_name('PID', 5)).to eq('patient_name')
      expect(described_class.field_name('OBX', 5)).to eq('observation_value')
      expect(described_class.field_name('MSH', 9)).to eq('message_type')
    end

    it 'falls back to field_<position> for unnamed fields' do
      expect(described_class.field_name('PID', 40)).to eq('field_40')
    end

    it 'falls back to field_<position> for unknown segments' do
      expect(described_class.field_name('ZXT', 2)).to eq('field_2')
    end
  end

  describe '.field_position' do
    it 'resolves names, field_<n> keys and bare numbers' do
      expect(described_class.field_position('PID', 'patient_name')).to eq(5)
      expect(described_class.field_position('PID', 'field_40')).to eq(40)
      expect(described_class.field_position('ZXT', '3')).to eq(3)
      expect(described_class.field_position('ZXT', :field_2)).to eq(2)
    end

    it 'rejects unknown names' do
      expect { described_class.field_position('PID', 'shoe_size') }
        .to raise_error(Hl7Gateway::EncodeError, /Unknown field "shoe_size" for segment PID/)
    end

    it 'rejects position zero' do
      expect { described_class.field_position('PID', '0') }.to raise_error(Hl7Gateway::EncodeError)
    end
  end

  it 'has unique names inside each segment' do
    described_class::FIELD_NAMES.each do |segment, names|
      expect(names.values.uniq.length).to eq(names.length), "duplicate field name in #{segment}"
    end
  end
end
