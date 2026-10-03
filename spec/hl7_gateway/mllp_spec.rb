# frozen_string_literal: true

RSpec.describe Hl7Gateway::MLLP do
  let(:vt) { "\x0B" }
  let(:fs_cr) { "\x1C\r" }

  describe '.frame' do
    it 'wraps the payload between the start and end blocks' do
      expect(described_class.frame("MSH|^~\\&|A\r")).to eq("\x0BMSH|^~\\&|A\r\x1C\r".b)
    end

    it 'returns binary data so multibyte payloads are not re-encoded' do
      expect(described_class.frame('Müller').encoding).to eq(Encoding::BINARY)
    end
  end

  describe '.unframe' do
    it 'extracts the payload and ignores bytes outside the frame' do
      expect(described_class.unframe("noise#{vt}payload#{fs_cr}tail")).to eq('payload'.b)
    end

    it 'fails when there is no complete frame' do
      expect { described_class.unframe("#{vt}payload") }.to raise_error(Hl7Gateway::FramingError)
      expect { described_class.unframe('payload') }.to raise_error(Hl7Gateway::FramingError)
    end
  end

  describe Hl7Gateway::MLLP::Stream do
    let(:pipe) { IO.pipe }
    let(:reader) { pipe.first }
    let(:writer) { pipe.last }
    let(:max_bytes) { 1024 }
    let(:idle_timeout) { 0.2 }
    let(:stream) { described_class.new(reader, max_bytes: max_bytes, idle_timeout: idle_timeout) }

    after { [reader, writer].each { |io| io.close unless io.closed? } }

    it 'reads a single framed message' do
      writer.write("#{vt}MSH|one#{fs_cr}")

      expect(stream.read_message).to eq('MSH|one')
    end

    it 'reads several messages that arrive in one chunk' do
      writer.write("#{vt}first#{fs_cr}#{vt}second#{fs_cr}")

      expect([stream.read_message, stream.read_message]).to eq(%w[first second])
    end

    it 'reassembles a message that arrives in pieces' do
      reading = Thread.new { stream.read_message }
      ["#{vt}MSH|sp", 'lit acro', "ss chunks#{fs_cr}"].each do |piece|
        writer.write(piece)
        sleep 0.02
      end

      expect(reading.value).to eq('MSH|split across chunks')
    end

    it 'accepts an end block that is not followed by a carriage return' do
      writer.write("#{vt}no-cr\x1C#{vt}next#{fs_cr}")

      expect([stream.read_message, stream.read_message]).to eq(%w[no-cr next])
    end

    it 'skips noise between frames, including the CR of a previous frame' do
      writer.write("#{vt}a#{fs_cr}\r\n junk #{vt}b#{fs_cr}")

      expect([stream.read_message, stream.read_message]).to eq(%w[a b])
    end

    it 'returns nil when the peer closes the connection between messages' do
      writer.write("#{vt}only#{fs_cr}")
      writer.close

      expect([stream.read_message, stream.read_message]).to eq(['only', nil])
    end

    it 'returns nil when the connection stays idle' do
      expect(stream.read_message).to be_nil
    end

    it 'fails when the connection closes in the middle of a message' do
      writer.write("#{vt}truncated")
      writer.close

      expect { stream.read_message }.to raise_error(Hl7Gateway::FramingError, /closed in the middle/)
    end

    it 'fails when a message stalls before its end block' do
      writer.write("#{vt}stalled")

      expect { stream.read_message }.to raise_error(Hl7Gateway::FramingError, /Timed out/)
    end

    context 'with a small size limit' do
      let(:max_bytes) { 64 }

      it 'rejects oversized messages' do
        writer.write("#{vt}#{'X' * 200}")

        expect { stream.read_message }.to raise_error(Hl7Gateway::FramingError, /exceeds 64 bytes/)
      end
    end
  end
end
