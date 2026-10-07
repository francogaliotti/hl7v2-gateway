# frozen_string_literal: true

RSpec.describe Hl7Gateway::Field do
  describe '.parse' do
    it 'returns nil for empty fields' do
      expect(described_class.parse('')).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end

    it 'keeps plain values as strings' do
      expect(described_class.parse('hello')).to eq('hello')
    end

    it 'keys components by their 1-based position' do
      expect(described_class.parse('DOE^JOHN^Q')).to eq('1' => 'DOE', '2' => 'JOHN', '3' => 'Q')
    end

    it 'skips empty components but keeps positions' do
      expect(described_class.parse('123^^^HOSP^MR')).to eq('1' => '123', '4' => 'HOSP', '5' => 'MR')
    end

    it 'parses sub-components' do
      expect(described_class.parse('a&b^c')).to eq('1' => { '1' => 'a', '2' => 'b' }, '2' => 'c')
    end

    it 'parses sub-components of a single component' do
      expect(described_class.parse('a&b')).to eq('1' => { '1' => 'a', '2' => 'b' })
    end

    it 'turns repetitions into an array' do
      expect(described_class.parse('555-1~555-2')).to eq(%w[555-1 555-2])
    end

    it 'repeats composite values' do
      expect(described_class.parse('a^b~c^d')).to eq([{ '1' => 'a', '2' => 'b' }, { '1' => 'c', '2' => 'd' }])
    end

    it 'keeps the position of empty repetitions' do
      expect(described_class.parse('a~~b')).to eq(['a', nil, 'b'])
    end

    it 'decodes escape sequences in leaf values only' do
      expect(described_class.parse('AT\\T\\T^R\\F\\D')).to eq('1' => 'AT&T', '2' => 'R|D')
    end

    it 'uses the delimiters it is given' do
      custom = Hl7Gateway::Delimiters.new(field: '#', component: '$', repetition: '*', escape: '!', subcomponent: '@')

      expect(described_class.parse('a$b*c', custom)).to eq([{ '1' => 'a', '2' => 'b' }, 'c'])
    end
  end

  describe '.serialize' do
    it 'renders nil as an empty field' do
      expect(described_class.serialize(nil)).to eq('')
    end

    it 'renders scalars, escaping delimiters' do
      expect(described_class.serialize('AT&T | R^D')).to eq('AT\\T\\T \\F\\ R\\S\\D')
    end

    it 'renders numbers and booleans as text' do
      expect([described_class.serialize(12), described_class.serialize(1.5)]).to eq(%w[12 1.5])
    end

    it 'fills the gaps between sparse components' do
      expect(described_class.serialize('1' => '123', '4' => 'HOSP', '5' => 'MR')).to eq('123^^^HOSP^MR')
    end

    it 'accepts symbol and out-of-order keys' do
      expect(described_class.serialize('2' => 'B', 1 => 'A')).to eq('A^B')
    end

    it 'renders sub-components and repetitions' do
      value = [{ '1' => { '1' => 'a', '2' => 'b' }, '2' => 'c' }, 'd']

      expect(described_class.serialize(value)).to eq('a&b^c~d')
    end

    it 'rejects component keys that are not positive integers' do
      expect { described_class.serialize('first' => 'x') }.to raise_error(Hl7Gateway::EncodeError, /positive integers/)
      expect { described_class.serialize('0' => 'x') }.to raise_error(Hl7Gateway::EncodeError)
    end

    it 'rejects structures deeper than the HL7 model allows' do
      expect { described_class.serialize([['a']]) }.to raise_error(Hl7Gateway::EncodeError, /nested/)
      expect { described_class.serialize('1' => ['a']) }.to raise_error(Hl7Gateway::EncodeError, /repetitions/)
      expect { described_class.serialize('1' => { '1' => { '1' => 'a' } }) }.to raise_error(Hl7Gateway::EncodeError, /nested/)
    end

    it 'is the inverse of parse' do
      %w[plain DOE^JOHN 123^^^HOSP^MR a&b^c 555-1~555-2 a~~b].each do |raw|
        expect(described_class.serialize(described_class.parse(raw))).to eq(raw)
      end
    end
  end

  describe '.component' do
    it 'reads components of composite fields' do
      expect(described_class.component({ '1' => 'ORU', '2' => 'R01' }, 2)).to eq('R01')
    end

    it 'treats a plain value as its own first component' do
      expect(described_class.component('ORU')).to eq('ORU')
      expect(described_class.component('ORU', 2)).to be_nil
    end

    it 'looks at the first repetition' do
      expect(described_class.component([{ '1' => 'a' }, { '1' => 'b' }])).to eq('a')
    end

    it 'unwraps sub-components to their first part' do
      expect(described_class.component({ '1' => { '1' => 'x', '2' => 'y' } })).to eq('x')
    end

    it 'returns nil for nil' do
      expect(described_class.component(nil)).to be_nil
    end
  end
end
