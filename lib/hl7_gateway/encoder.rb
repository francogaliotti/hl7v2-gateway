# frozen_string_literal: true

require 'ruby-hl7'

module Hl7Gateway
  # JSON document -> HL7 v2 text. The mirror image of Decoder.
  #
  # Segments are instantiated as ruby-hl7 classes (MSH, PID, OBX ... or the generic segment
  # for custom Z-segments) and assembled into an HL7::Message, which takes care of segment
  # ordering and of numbering consecutive repeating segments (OBX-1, NTE-1 ...).
  module Encoder
    SEGMENT_ID = Decoder::SEGMENT_ID

    module_function

    # Returns the message with every segment, the last one included, terminated by <CR>.
    def call(document)
      segments = Document.segments(document)
      raise EncodeError, 'Document has no segments' if segments.empty?

      msh = segments.first
      raise EncodeError, 'The first segment must be MSH' unless msh.is_a?(Hash) && msh['segment'] == 'MSH'

      delimiters = delimiters_for(msh.fetch('fields', {}))
      message = HL7::Message.new
      segments.each { |segment| message << build_segment(segment, delimiters) }
      "#{message.to_hl7}\r"
    end

    def delimiters_for(msh_fields)
      field = msh_fields['field_separator'] || Delimiters::DEFAULT.field
      encoding = msh_fields['encoding_characters'] || Delimiters::DEFAULT.encoding_characters
      raise EncodeError, 'MSH-1 must be a single character' unless field.to_s.length == 1

      Delimiters.from_msh("MSH#{field}#{encoding}#{field}")
    rescue ParseError => e
      raise EncodeError, e.message
    end

    def build_segment(segment, delimiters)
      raise EncodeError, 'Every segment must be an object' unless segment.is_a?(Hash)

      name = segment['segment'].to_s
      raise EncodeError, "Invalid segment id #{name.inspect}" unless name.match?(SEGMENT_ID)

      fields = segment['fields'] || {}
      raise EncodeError, "Fields of #{name} must be an object" unless fields.is_a?(Hash)

      segment_class(name).new(serialize_segment(name, fields, delimiters), [delimiters.field, delimiters.component])
    end

    def serialize_segment(name, fields, delimiters)
      header = name == 'MSH'
      elements = [name]
      elements[1] = delimiters.encoding_characters if header

      fields.each do |key, value|
        position = Schema.field_position(name, key)
        next if header && position <= 2

        elements[header ? position - 1 : position] = Field.serialize(value, delimiters)
      end

      elements.join(delimiters.field)
    end

    def segment_class(name)
      klass = HL7::Message::Segment.const_defined?(name, false) && HL7::Message::Segment.const_get(name, false)
      klass.is_a?(Class) && klass < HL7::Message::Segment ? klass : HL7::Message::Segment::Default
    end
  end
end
