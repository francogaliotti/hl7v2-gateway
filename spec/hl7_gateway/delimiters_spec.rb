# frozen_string_literal: true

RSpec.describe Hl7Gateway::Delimiters do
  describe '.from_msh' do
    it 'reads the standard delimiters' do
      delimiters = described_class.from_msh("MSH|^~\\&|APP\r")

      expect(delimiters).to have_attributes(field: '|', component: '^', repetition: '~', escape: '\\', subcomponent: '&')
    end

    it 'reads custom delimiters' do
      delimiters = described_class.from_msh('MSH#$*\\@#APP')

      expect(delimiters).to have_attributes(field: '#', component: '$', repetition: '*', escape: '\\', subcomponent: '@')
    end

    it 'defaults the sub-component separator when MSH-2 has only three characters' do
      expect(described_class.from_msh('MSH|^~\\|APP').subcomponent).to eq('&')
    end

    it 'rejects text that is not an MSH segment' do
      expect { described_class.from_msh('PID|1') }.to raise_error(Hl7Gateway::ParseError)
    end

    it 'rejects an MSH without encoding characters' do
      expect { described_class.from_msh('MSH|APP') }.to raise_error(Hl7Gateway::ParseError, /encoding characters/)
    end

    it 'rejects repeated encoding characters' do
      expect { described_class.from_msh('MSH|^^\\&|APP') }.to raise_error(Hl7Gateway::ParseError, /distinct/)
    end
  end

  describe '#encoding_characters' do
    it 'renders the value of MSH-2' do
      expect(described_class::DEFAULT.encoding_characters).to eq('^~\\&')
    end
  end
end
