# frozen_string_literal: true

module Hl7Helpers
  FIXTURES = File.expand_path('../fixtures', __dir__)

  # Fixtures are stored with newlines for readability; HL7 uses <CR> between segments.
  def hl7_fixture(name)
    File.read(File.join(FIXTURES, "#{name}.hl7")).gsub("\n", "\r")
  end

  def hl7(*segments)
    "#{segments.join("\r")}\r"
  end
end

RSpec.configure { |config| config.include Hl7Helpers }
