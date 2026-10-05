# frozen_string_literal: true

RSpec.describe Hl7Gateway::Sanitizer do
  let(:msh) { 'MSH|^~\\&|A|B|C|D|20261001||ADT^A01|1|P|2.5' }

  it 'uses <CR> as the only segment separator and terminates the last segment' do
    expect(described_class.call("#{msh}\nPID|1\r\nPV1|1")).to eq("#{msh}\rPID|1\rPV1|1\r")
  end

  it 'is idempotent' do
    once = described_class.call("#{msh}\nPID|1")

    expect(described_class.call(once)).to eq(once)
  end

  it 'drops blank lines and trailing separators' do
    expect(described_class.call("#{msh}\r\r\n\nPID|1\r\r")).to eq("#{msh}\rPID|1\r")
  end

  it 'discards anything before the MSH segment' do
    expect(described_class.call("banner\n  \n#{msh}\nPID|1")).to eq("#{msh}\rPID|1\r")
  end

  it 'removes a byte order mark' do
    expect(described_class.call("﻿#{msh}")).to eq("#{msh}\r")
  end

  it 'fails when there is no MSH segment' do
    expect { described_class.call("PID|1\rPV1|1") }.to raise_error(Hl7Gateway::ParseError, /MSH/)
    expect { described_class.call('') }.to raise_error(Hl7Gateway::ParseError)
  end

  describe 'character sets' do
    it 'decodes UTF-8 by default' do
      raw = "#{msh}\rPID|1||||Ångström^Zoë".b

      expect(described_class.call(raw)).to include('Ångström^Zoë')
    end

    it 'honours the charset declared in MSH-18' do
      header = 'MSH|^~\\&|A|B|C|D|20261001||ADT^A01|1|P|2.5||||||8859/1'
      raw = "#{header}\rPID|1||||Müller".encode('ISO-8859-1').b

      result = described_class.call(raw)

      expect(result).to include('Müller')
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'falls back to ISO-8859-1 when undeclared bytes are not valid UTF-8' do
      raw = "#{msh}\rPID|1||||Müller".encode('ISO-8859-1').b

      expect(described_class.call(raw)).to include('Müller')
    end
  end
end
