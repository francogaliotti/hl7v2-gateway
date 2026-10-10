# frozen_string_literal: true

RSpec.describe 'HL7 <-> JSON round trip' do
  %w[oru_r01 adt_a01 custom_delimiters].each do |name|
    context "with #{name}.hl7" do
      let(:original) { hl7_fixture(name) }

      it 'reproduces the original message byte for byte' do
        document = Hl7Gateway::Decoder.call(original)

        expect(Hl7Gateway::Encoder.call(document)).to eq(original)
      end

      it 'survives a trip through real JSON text' do
        json = JSON.generate(Hl7Gateway::Decoder.call(original))

        expect(Hl7Gateway::Encoder.call(JSON.parse(json))).to eq(original)
      end
    end
  end

  it 'preserves special characters in free text' do
    note = "50% R&D | AT&T ~ a^b \\ done\nnext line"
    document = Hl7Gateway::Decoder.call(hl7('MSH|^~\\&|A|B|C|D|20261001||ORU^R01|1|P|2.5'))
    document['segments'] << { 'segment' => 'NTE', 'fields' => { 'comment' => note } }

    decoded = Hl7Gateway::Decoder.call(Hl7Gateway::Encoder.call(document))

    expect(Hl7Gateway::Document.fields(decoded, 'NTE')['comment']).to eq(note)
  end

  it 'preserves non-ASCII text' do
    message = hl7('MSH|^~\\&|A|B|C|D|20261001||ORU^R01|1|P|2.5||||||UNICODE UTF-8', 'PID|1||||Ångström^Zoë')

    expect(Hl7Gateway::Encoder.call(Hl7Gateway::Decoder.call(message))).to eq(message)
  end
end
