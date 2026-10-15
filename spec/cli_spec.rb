# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'command line tools' do
  ROOT = File.expand_path('..', __dir__)

  def run_tool(name, *args, stdin: '', env: {})
    Open3.capture3(env, RbConfig.ruby, File.join(ROOT, 'bin', name), *args, stdin_data: stdin)
  end

  describe 'hl7-to-json' do
    it 'prints the JSON document of a message read from stdin' do
      out, _err, status = run_tool('hl7-to-json', '--compact', stdin: hl7_fixture('adt_a01'))

      expect(status).to be_success
      expect(JSON.parse(out)).to include('message_type' => 'ADT^A01', 'control_id' => 'MSG00043')
    end

    it 'reads files' do
      out, _err, status = run_tool('hl7-to-json', File.join(ROOT, 'examples/messages/oru_r01.hl7'))

      expect(status).to be_success
      expect(JSON.parse(out)['segments'].map { |segment| segment['segment'] }).to eq(%w[MSH PID OBR OBX NTE])
    end

    it 'fails with a readable message on invalid input' do
      _out, err, status = run_tool('hl7-to-json', stdin: 'not hl7')

      expect(status).not_to be_success
      expect(err).to include('hl7-to-json: Message must contain an MSH segment')
    end
  end

  describe 'json-to-hl7' do
    let(:document) { JSON.generate(Hl7Gateway::Decoder.call(hl7_fixture('adt_a01'))) }

    it 'prints one segment per line' do
      out, _err, status = run_tool('json-to-hl7', stdin: document)

      expect(status).to be_success
      expect(out.lines.map(&:chomp)).to eq(hl7_fixture('adt_a01').split("\r"))
    end

    it 'can emit real carriage returns' do
      out, _err, _status = run_tool('json-to-hl7', '--cr', stdin: document)

      expect(out).to eq(hl7_fixture('adt_a01'))
    end

    it 'fails on invalid JSON and on invalid documents' do
      _out, err, status = run_tool('json-to-hl7', stdin: '{oops')
      expect(status).not_to be_success
      expect(err).to match(/invalid JSON/)

      _out, err, status = run_tool('json-to-hl7', stdin: '{"segments":[]}')
      expect(status).not_to be_success
      expect(err).to match(/no segments/)
    end
  end

  describe 'hl7-gateway' do
    it 'refuses to start without UPSTREAM_API_URL' do
      _out, err, status = run_tool('hl7-gateway', env: { 'UPSTREAM_API_URL' => nil })

      expect(status.exitstatus).to eq(1)
      expect(err).to include('UPSTREAM_API_URL is required')
    end

    it 'prints its usage' do
      out, _err, status = run_tool('hl7-gateway', '--help')

      expect(status).to be_success
      expect(out).to include('UPSTREAM_API_URL')
    end
  end

  describe 'hl7-send' do
    it 'reports a refused connection' do
      _out, err, status = run_tool('hl7-send', '--port', '1', '-', stdin: hl7_fixture('adt_a01'))

      expect(status).not_to be_success
      expect(err).to include('hl7-send:')
    end
  end
end
