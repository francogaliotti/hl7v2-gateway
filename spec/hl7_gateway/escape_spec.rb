# frozen_string_literal: true

RSpec.describe Hl7Gateway::Escape do
  let(:delimiters) { Hl7Gateway::Delimiters::DEFAULT }

  describe '.decode' do
    {
      'a\\F\\b' => 'a|b',
      'a\\S\\b' => 'a^b',
      'a\\T\\b' => 'a&b',
      'a\\R\\b' => 'a~b',
      'a\\E\\b' => 'a\\b',
      'line1\\.br\\line2' => "line1\nline2",
      'plain \\H\\bold\\N\\ text' => 'plain bold text',
      'caf\\XC3A9\\' => 'café'
    }.each do |escaped, expected|
      it "turns #{escaped.inspect} into #{expected.inspect}" do
        expect(described_class.decode(escaped, delimiters)).to eq(expected)
      end
    end

    it 'leaves unknown sequences untouched' do
      expect(described_class.decode('keep \\Zxx\\ this', delimiters)).to eq('keep \\Zxx\\ this')
    end

    it 'leaves invalid hexadecimal data untouched' do
      expect(described_class.decode('bad \\XFF\\ byte', delimiters)).to eq('bad \\XFF\\ byte')
    end

    it 'honours custom delimiters' do
      custom = Hl7Gateway::Delimiters.new(field: '#', component: '$', repetition: '*', escape: '!', subcomponent: '@')

      expect(described_class.decode('a!F!b!S!c', custom)).to eq('a#b$c')
    end
  end

  describe '.encode' do
    it 'escapes every special character' do
      expect(described_class.encode('a|b^c&d~e\\f', delimiters)).to eq('a\\F\\b\\S\\c\\T\\d\\R\\e\\E\\f')
    end

    it 'turns line breaks into \\.br\\' do
      expect(described_class.encode("one\r\ntwo\nthree", delimiters)).to eq('one\\.br\\two\\.br\\three')
    end

    it 'does not escape twice' do
      expect(described_class.encode('\\F\\', delimiters)).to eq('\\E\\F\\E\\')
    end

    it 'round trips with decode' do
      text = "R&D | team ~ 50% ^ cost \\ plan\nnext line"

      expect(described_class.decode(described_class.encode(text, delimiters), delimiters)).to eq(text)
    end
  end
end
