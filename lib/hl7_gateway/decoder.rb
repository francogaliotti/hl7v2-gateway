# frozen_string_literal: true

require 'ruby-hl7'

module Hl7Gateway
  # HL7 v2 text -> JSON-ready document.
  #
  # ruby-hl7 does the heavy lifting of splitting the message into typed segments; this
  # module adds what the gem leaves out: MSH validation, delimiter discovery, component /
  # repetition / sub-component parsing, escape sequences and field naming.
  module Decoder
    SEGMENT_ID = /\A[A-Z][A-Z0-9]{2}\z/

    module_function

    def call(raw)
      text = Sanitizer.call(raw)
      delimiters = Delimiters.from_msh(text)
      validate_segment_ids(text, delimiters)

      segments = parse_with_ruby_hl7(text).map { |segment| decode_segment(segment, delimiters) }
      header = segments.first.fetch('fields')

      {
        'message_type' => message_type(header['message_type']),
        'control_id' => Field.component(header['message_control_id']),
        'version' => Field.component(header['version_id']),
        'segments' => segments
      }.compact
    end

    # Best-effort read of the MSH of a message that failed to parse, so the rejection can
    # still be addressed to the right sender and reference the right control id.
    def peek_header(raw)
      text = Sanitizer.call(raw)
      delimiters = Delimiters.from_msh(text)
      elements = text.lines("\r").first.chomp("\r").split(delimiters.field, -1)
      { 'segments' => [decode_segment(elements, delimiters)] }
    rescue Error
      { 'segments' => [] }
    end

    def parse_with_ruby_hl7(text)
      HL7::Message.new(text.chomp("\r"))
    rescue HL7::Exception => e
      raise ParseError, "Unable to parse HL7 message (#{e.class.name.split('::').last})"
    end

    def validate_segment_ids(text, delimiters)
      text.split("\r").each_with_index do |line, index|
        id = line.split(delimiters.field, 2).first.to_s
        raise ParseError, "Line #{index + 1} does not start with a valid segment id" unless id.match?(SEGMENT_ID)
      end
    end

    def decode_segment(segment, delimiters)
      name = segment[0].to_s
      header = name == 'MSH'
      fields = {}
      fields[Schema.field_name(name, 1)] = delimiters.field if header

      (1...segment.length).each do |index|
        position = header ? index + 1 : index
        raw = segment[index].to_s
        value = header && position == 2 ? raw : Field.parse(raw, delimiters)
        fields[Schema.field_name(name, position)] = value unless value.nil? || value == ''
      end

      { 'segment' => name, 'fields' => fields }
    end

    def message_type(value)
      parts = [Field.component(value, 1), Field.component(value, 2)].compact
      parts.empty? ? nil : parts.join('^')
    end
  end
end
