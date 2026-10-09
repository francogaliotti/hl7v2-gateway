# frozen_string_literal: true

module Hl7Gateway
  # Read-only helpers for the JSON document shape:
  #
  #   {
  #     "message_type": "ORU^R01",
  #     "control_id": "MSG0001",
  #     "version": "2.5",
  #     "segments": [{ "segment": "MSH", "fields": { "sending_application": "LAB", ... } }, ...]
  #   }
  module Document
    module_function

    def segments(document, name = nil)
      list = document.is_a?(Hash) ? Array(document['segments']) : []
      name ? list.select { |segment| segment.is_a?(Hash) && segment['segment'] == name } : list
    end

    def segment(document, name)
      segments(document, name).first
    end

    # Fields of the first segment called `name`; an empty hash when there is none.
    def fields(document, name)
      segment(document, name)&.fetch('fields', nil) || {}
    end

    # Splits `ORU^R01`-style strings into the component structure used by the documents.
    def composite(text)
      Field.parse(text.to_s)
    end
  end
end
