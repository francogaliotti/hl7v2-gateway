# frozen_string_literal: true

module Hl7Gateway
  # Converts a single HL7 field to and from its JSON representation.
  #
  #   "plain"                  -> "plain"
  #   "DOE^JOHN"               -> { "1" => "DOE", "2" => "JOHN" }
  #   "123^^^HOSP^MR"          -> { "1" => "123", "4" => "HOSP", "5" => "MR" }
  #   "a&b^c"                  -> { "1" => { "1" => "a", "2" => "b" }, "2" => "c" }
  #   "555-1234~555-9876"      -> ["555-1234", "555-9876"]
  #
  # Components and sub-components are keyed by their 1-based HL7 position, exactly as in
  # the usual PID-3.4 notation, so sparse values stay readable and survive a round trip.
  # Repetitions become JSON arrays. Empty values are `nil`.
  module Field
    module_function

    def parse(raw, delimiters = Delimiters::DEFAULT)
      return nil if raw.nil? || raw.empty?

      repetitions = raw.split(delimiters.repetition, -1).map { |repetition| parse_repetition(repetition, delimiters) }
      repetitions.length == 1 ? repetitions.first : repetitions
    end

    def serialize(value, delimiters = Delimiters::DEFAULT)
      case value
      when nil then ''
      when Array then value.map { |repetition| serialize_repetition(repetition, delimiters) }.join(delimiters.repetition)
      else serialize_repetition(value, delimiters)
      end
    end

    # Returns component `position` of a field, whatever its shape (plain, composite or repeating).
    # Only the first repetition is considered.
    def component(value, position = 1)
      value = value.first if value.is_a?(Array)

      case value
      when nil then nil
      when Hash then first_scalar(value[position.to_s])
      else position == 1 ? value : nil
      end
    end

    def first_scalar(value)
      value.is_a?(Hash) ? value['1'] : value
    end

    def parse_repetition(repetition, delimiters)
      return nil if repetition.empty?

      components = repetition.split(delimiters.component, -1)
      return Escape.decode(repetition, delimiters) if components.length == 1 && !repetition.include?(delimiters.subcomponent)

      positional(components) { |component| parse_component(component, delimiters) }
    end

    def parse_component(component, delimiters)
      return nil if component.empty?

      subcomponents = component.split(delimiters.subcomponent, -1)
      return Escape.decode(component, delimiters) if subcomponents.length == 1

      positional(subcomponents) { |subcomponent| subcomponent.empty? ? nil : Escape.decode(subcomponent, delimiters) }
    end

    def positional(parts)
      result = {}
      parts.each_with_index do |part, index|
        value = yield(part)
        result[(index + 1).to_s] = value unless value.nil?
      end
      result.empty? ? nil : result
    end

    def serialize_repetition(value, delimiters)
      case value
      when nil then ''
      when Hash then join_positions(value, delimiters.component) { |component| serialize_component(component, delimiters) }
      when Array then raise EncodeError, 'Repetitions cannot be nested'
      else Escape.encode(value.to_s, delimiters)
      end
    end

    def serialize_component(component, delimiters)
      case component
      when nil then ''
      when Hash then join_positions(component, delimiters.subcomponent) { |sub| serialize_subcomponent(sub, delimiters) }
      when Array then raise EncodeError, 'Components cannot contain repetitions'
      else Escape.encode(component.to_s, delimiters)
      end
    end

    def serialize_subcomponent(subcomponent, delimiters)
      raise EncodeError, 'Sub-components cannot be nested any further' if subcomponent.is_a?(Hash) || subcomponent.is_a?(Array)

      subcomponent.nil? ? '' : Escape.encode(subcomponent.to_s, delimiters)
    end

    def join_positions(parts, separator)
      by_position = parts.each_with_object({}) do |(key, value), memo|
        position = Integer(key.to_s, 10, exception: false)
        raise EncodeError, "Component positions must be positive integers, got #{key.inspect}" unless position&.positive?

        memo[position] = value
      end
      return '' if by_position.empty?

      (1..by_position.keys.max).map { |position| yield(by_position[position]) }.join(separator)
    end
  end
end
