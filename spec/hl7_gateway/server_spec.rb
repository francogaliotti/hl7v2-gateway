# frozen_string_literal: true

RSpec.describe Hl7Gateway::Server do
  let(:processor) { instance_double(Hl7Gateway::Processor) }
  let(:idle_timeout) { 2 }
  let(:max_message_bytes) { 4096 }
  let(:server) do
    described_class.new(processor: processor, host: '127.0.0.1', port: 0, idle_timeout: idle_timeout,
                        max_message_bytes: max_message_bytes)
  end

  before { allow(processor).to receive(:call) { |payload| "MSH|echo|#{payload.bytesize}\r" } }

  around do |example|
    server.start
    example.run
  ensure
    server.stop(timeout: 1)
  end

  def connect(&block)
    TCPSocket.open('127.0.0.1', server.port, &block)
  end

  # One stream per socket: it buffers, so a fresh one could miss data already read.
  def read_frame(socket)
    @streams ||= {}.compare_by_identity
    @streams[socket] ||= Hl7Gateway::MLLP::Stream.new(socket, max_bytes: 4096, idle_timeout: 2)
    @streams[socket].read_message
  end

  it 'listens on the requested interface and a real port' do
    expect(server.port).to be_positive
  end

  it 'answers a framed message with a framed response' do
    connect do |socket|
      socket.write(Hl7Gateway::MLLP.frame("MSH|^~\\&|A\r"))

      expect(read_frame(socket)).to eq("MSH|echo|11\r")
    end
  end

  it 'hands the processor the exact payload that was framed' do
    connect do |socket|
      socket.write(Hl7Gateway::MLLP.frame('hello'))
      read_frame(socket)
    end

    expect(processor).to have_received(:call).with('hello'.b)
  end

  it 'serves several messages on one connection, in order' do
    connect do |socket|
      socket.write(Hl7Gateway::MLLP.frame('a') + Hl7Gateway::MLLP.frame('bb'))

      expect([read_frame(socket), read_frame(socket)]).to eq(["MSH|echo|1\r", "MSH|echo|2\r"])
    end
  end

  it 'serves concurrent connections' do
    gate = Queue.new
    allow(processor).to receive(:call) do |payload|
      gate.pop if payload == 'slow'
      "done-#{payload}\r"
    end

    slow = TCPSocket.new('127.0.0.1', server.port)
    slow.write(Hl7Gateway::MLLP.frame('slow'))

    connect do |socket|
      socket.write(Hl7Gateway::MLLP.frame('fast'))
      expect(read_frame(socket)).to eq("done-fast\r")
    end

    gate << :go
    expect(read_frame(slow)).to eq("done-slow\r")
    slow.close
  end

  it 'closes the connection when the client sends a truncated message' do
    connect do |socket|
      socket.write("\x0Bpartial")
      socket.close_write

      expect(socket.read).to eq('')
    end
  end

  context 'with a small message size limit' do
    let(:max_message_bytes) { 128 }

    it 'closes connections that send oversized messages and keeps serving others' do
      connect do |socket|
        socket.write("\x0B#{'X' * 500}")
        expect(socket.read).to eq('')
      end

      connect do |socket|
        socket.write(Hl7Gateway::MLLP.frame('ok'))
        expect(read_frame(socket)).to eq("MSH|echo|2\r")
      end
    end
  end

  context 'with a short idle timeout' do
    let(:idle_timeout) { 0.2 }

    it 'closes idle connections' do
      connect { |socket| expect(socket.read).to eq('') }
    end
  end

  describe '#stop' do
    it 'stops accepting connections' do
      port = server.port
      server.stop(timeout: 1)

      expect { TCPSocket.new('127.0.0.1', port) }.to raise_error(Errno::ECONNREFUSED)
    end

    it 'drops idle connections' do
      socket = TCPSocket.new('127.0.0.1', server.port)
      sleep 0.05

      server.stop(timeout: 1)

      expect(socket.read).to eq('')
      socket.close
    end

    it 'lets an in-flight message finish before closing' do
      release = Queue.new
      allow(processor).to receive(:call) do
        release.pop
        "late\r"
      end

      socket = TCPSocket.new('127.0.0.1', server.port)
      socket.write(Hl7Gateway::MLLP.frame('work'))
      sleep 0.1

      stopper = Thread.new { server.stop(timeout: 3) }
      sleep 0.1
      release << :go

      expect(read_frame(socket)).to eq("late\r")
      stopper.join
      socket.close
    end
  end
end
