# frozen_string_literal: true

module Hl7Gateway
  # The five special characters of an HL7 v2 message, announced in MSH-1 and MSH-2.
  Delimiters = Struct.new(:field, :component, :repetition, :escape, :subcomponent, keyword_init: true) do
    # Reads the delimiters from the first characters of an MSH segment (`MSH|^~\&|...`).
    def self.from_msh(text)
      raise ParseError, 'Message must start with an MSH segment' unless text.to_s.start_with?('MSH')

      field = text[3]
      raise ParseError, 'MSH segment has no field separator' if field.nil? || field.match?(/[\r\n]/)

      closing = text.index(field, 4)
      raise ParseError, 'MSH segment has no encoding characters' unless closing

      encoding = text[4...closing]
      unless [3, 4].include?(encoding.length) && encoding.chars.uniq.length == encoding.length
        raise ParseError, 'MSH-2 must contain three or four distinct encoding characters'
      end

      new(field: field, component: encoding[0], repetition: encoding[1], escape: encoding[2],
          subcomponent: encoding[3] || '&')
    end

    # `^~\&`, as it is written in MSH-2.
    def encoding_characters
      "#{component}#{repetition}#{escape}#{subcomponent}"
    end
  end

  Delimiters::DEFAULT = Delimiters.new(field: '|', component: '^', repetition: '~', escape: '\\', subcomponent: '&').freeze
end
