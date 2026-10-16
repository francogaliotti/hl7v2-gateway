# frozen_string_literal: true

require_relative '../examples/mock_api'

# Boots the real gateway in front of the real example API and talks to it over TCP,
# exactly like an HL7 sender would.
RSpec.describe 'gateway end to end' do
  before(:context) do
    WebMock.allow_net_connect!
    @api = MockApi.server(port: 0, logger: WEBrick::Log.new(File::NULL))
    @api_thread = Thread.new { @api.start }

    config = Hl7Gateway::Config.new(upstream_url: "http://127.0.0.1:#{@api.listeners.first.addr[1]}/api/messages",
                                    sending_application: 'GATEWAY', sending_facility: 'TEST')
    processor = Hl7Gateway::Processor.new(client: Hl7Gateway::UpstreamClient.new(config), config: config)
    @server = Hl7Gateway::Server.new(processor: processor, host: '127.0.0.1', port: 0, idle_timeout: 2,
                                     max_message_bytes: 65_536).start
  end

  after(:context) do
    @server.stop(timeout: 1)
    @api.shutdown
    @api_thread.join(2)
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def exchange(message)
    TCPSocket.open('127.0.0.1', @server.port) do |socket|
      socket.write(Hl7Gateway::MLLP.frame(message))
      reply = Hl7Gateway::MLLP::Stream.new(socket, max_bytes: 65_536, idle_timeout: 5).read_message
      Hl7Gateway::Decoder.call(reply)
    end
  end

  def example_message(name)
    File.read(File.expand_path("../examples/messages/#{name}.hl7", __dir__))
  end

  it 'computes a result through the API and returns it as an HL7 ORU' do
    response = exchange(example_message('bmi_request'))

    expect(response['message_type']).to eq('ORU^R01')
    expect(Hl7Gateway::Document.fields(response, 'MSA')).to include('acknowledgment_code' => 'AA', 'message_control_id' => 'CTRL-0001')
    expect(Hl7Gateway::Document.fields(response, 'PID')['patient_name']).to eq('1' => 'MARTINEZ', '2' => 'ELENA', '3' => 'R')

    bmi, category = Hl7Gateway::Document.segments(response, 'OBX').map { |segment| segment['fields'] }
    expect(bmi).to include('observation_value' => '23.2', 'units' => 'kg/m2', 'abnormal_flags' => 'N')
    expect(category).to include('observation_value' => 'Normal')
  end

  it 'acknowledges messages the API only needs to know about' do
    response = exchange(example_message('adt_a01'))

    expect(response['message_type']).to eq('ACK^A01')
    expect(Hl7Gateway::Document.fields(response,
                                       'MSA')).to include('acknowledgment_code' => 'AA', 'text_message' => 'Patient event recorded')
  end

  it 'turns an API validation error into an AE with the API text' do
    response = exchange(example_message('bmi_missing_height'))

    expect(Hl7Gateway::Document.fields(response, 'MSA')).to include(
      'acknowledgment_code' => 'AE', 'message_control_id' => 'CTRL-0004',
      'text_message' => 'Body weight and body height observations are required'
    )
  end

  it 'rejects garbage with an AR instead of dropping the connection' do
    response = exchange("MSH|^~\\&|CLINIC|SITE|||||ORM^O01|CTRL-77|P|2.5\rthis is not hl7")

    expect(Hl7Gateway::Document.fields(response, 'MSA')).to include('acknowledgment_code' => 'AR', 'message_control_id' => 'CTRL-77')
  end
end
