# frozen_string_literal: true

module Hl7Gateway
  # Turns whatever arrived on the wire into a clean, UTF-8, CR-delimited HL7 string.
  #
  # Real-world senders disagree on line endings, add banners before the MSH, leave blank
  # lines behind and do not always declare their character set. This is the one place that
  # copes with all of that so the rest of the pipeline can assume well-formed text.
  module Sanitizer
    # MSH-18 values (HL7 table 0211) mapped to Ruby encodings.
    CHARSETS = {
      'ASCII' => 'US-ASCII',
      '8859/1' => 'ISO-8859-1',
      '8859/15' => 'ISO-8859-15',
      'UNICODE' => 'UTF-8',
      'UNICODE UTF-8' => 'UTF-8'
    }.freeze

    module_function

    def call(payload)
      text = to_utf8(payload.to_s.b)
      text = text.delete_prefix("\uFEFF").delete("\v\x1C") # BOM and MLLP block characters
      lines = text.split(/\r\n|\r|\n/)

      first = lines.index { |line| line.start_with?('MSH') }
      raise ParseError, 'Message must contain an MSH segment' unless first

      lines[first..].reject { |line| line.strip.empty? }.map { |line| "#{line}\r" }.join
    end

    def to_utf8(binary)
      [declared_charset(binary), 'UTF-8', 'ISO-8859-1'].compact.uniq.each do |encoding|
        candidate = binary.dup.force_encoding(encoding)
        return candidate.encode('UTF-8') if candidate.valid_encoding?
      end
    end

    # Reads MSH-18 straight from the bytes, before the text can be interpreted safely.
    def declared_charset(binary)
      header = binary[/MSH[^\r\n]*/n]
      return nil unless header && header.length > 3

      separator = header[3]
      charset = header.split(separator, -1)[17].to_s.split(header[5].to_s).first.to_s.strip.upcase
      CHARSETS[charset]
    end
  end
end
