# frozen_string_literal: true

module Hl7Gateway
  # HL7 escape sequences (\F\, \S\, \T\, \R\, \E\, \.br\, \Xhh\ ...).
  module Escape
    module_function

    # Replaces escape sequences found in a leaf value with the characters they stand for.
    # Unknown sequences are left untouched so no information is lost.
    def decode(text, delimiters)
      escape = delimiters.escape
      return text unless text.include?(escape)

      pattern = /#{Regexp.escape(escape)}([^#{Regexp.escape(escape)}]*)#{Regexp.escape(escape)}/
      text.gsub(pattern) do
        match = Regexp.last_match
        decode_sequence(match[1], delimiters) || match[0]
      end
    end

    # Makes a plain string safe to embed in an HL7 field.
    def encode(text, delimiters)
      replacements = {
        delimiters.escape => "#{delimiters.escape}E#{delimiters.escape}",
        delimiters.field => "#{delimiters.escape}F#{delimiters.escape}",
        delimiters.component => "#{delimiters.escape}S#{delimiters.escape}",
        delimiters.repetition => "#{delimiters.escape}R#{delimiters.escape}",
        delimiters.subcomponent => "#{delimiters.escape}T#{delimiters.escape}"
      }
      line_break = "#{delimiters.escape}.br#{delimiters.escape}"
      text.gsub(Regexp.union(*replacements.keys, /\r\n|\r|\n/)) { |char| replacements.fetch(char, line_break) }
    end

    def decode_sequence(sequence, delimiters)
      case sequence
      when 'F' then delimiters.field
      when 'S' then delimiters.component
      when 'T' then delimiters.subcomponent
      when 'R' then delimiters.repetition
      when 'E' then delimiters.escape
      when '.br' then "\n"
      when 'H', 'N' then ''
      when /\AX(?:\h{2})+\z/ then decode_hex(sequence[1..])
      end
    end

    def decode_hex(hex)
      decoded = [hex].pack('H*').force_encoding(Encoding::UTF_8)
      decoded.valid_encoding? ? decoded : nil
    end
  end
end
