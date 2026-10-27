# frozen_string_literal: true

RSpec.describe Hl7Gateway do
  it 'has a semantic version (MAJOR.MINOR.PATCH)' do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/)
  end

  it 'is the version published in the changelog' do
    changelog = File.read(File.expand_path('../../CHANGELOG.md', __dir__))

    expect(changelog).to match(/^## \[#{Regexp.escape(described_class::VERSION)}\]/)
  end
end
