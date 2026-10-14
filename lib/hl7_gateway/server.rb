# frozen_string_literal: true

require 'logger'
require 'socket'

module Hl7Gateway
  # Threaded MLLP listener. One thread per connection; a connection may carry any number
  # of messages and is answered strictly in order.
  class Server
    Connection = Struct.new(:socket, :busy)

    def initialize(processor:, host:, port:, idle_timeout:, max_message_bytes:, logger: Logger.new(nil))
      @processor = processor
      @host = host
      @requested_port = port
      @idle_timeout = idle_timeout
      @max_message_bytes = max_message_bytes
      @logger = logger
      @connections = {}
      @mutex = Mutex.new
      @stopping = false
    end

    # Port actually bound; useful when started with port 0.
    def port
      @listener&.addr&.fetch(1)
    end

    def start
      @listener = TCPServer.new(@host, @requested_port)
      @logger.info("MLLP server listening on #{@host}:#{port}")
      @acceptor = Thread.new { accept_loop }
      self
    end

    def join
      @acceptor&.join
    end

    # Stops accepting, drops idle connections right away and gives in-flight messages
    # `timeout` seconds to be answered.
    def stop(timeout: 5)
      @stopping = true
      @listener&.close
      @acceptor&.join(timeout)
      close_idle_connections

      deadline = Time.now + timeout
      workers = @mutex.synchronize { @connections.values.map { |entry| entry[:thread] } }
      workers.each { |thread| thread.join([deadline - Time.now, 0].max) }
      @mutex.synchronize { @connections.each_value { |entry| close_quietly(entry[:connection].socket) } }
      @logger.info('MLLP server stopped')
    end

    private

    def accept_loop
      until @stopping
        socket = @listener.accept
        register(socket)
      end
    rescue IOError, Errno::EBADF
      nil # listener closed by #stop
    end

    def register(socket)
      connection = Connection.new(socket, false)
      # The worker takes the mutex when it finishes, so it cannot deregister before it is registered.
      @mutex.synchronize do
        @connections[connection] = { connection: connection, thread: Thread.new { serve(connection) } }
      end
    end

    def serve(connection)
      peer = peer_name(connection.socket)
      @logger.debug("Connection opened from #{peer}")
      stream = MLLP::Stream.new(connection.socket, max_bytes: @max_message_bytes, idle_timeout: @idle_timeout)

      while (payload = stream.read_message)
        mark_busy(connection, true)
        connection.socket.write(MLLP.frame(@processor.call(payload)))
        mark_busy(connection, false)
        break if @stopping
      end
    rescue FramingError => e
      @logger.warn("Closing connection from #{peer}: #{e.message}")
    rescue IOError, SystemCallError
      @logger.debug("Connection from #{peer} dropped")
    ensure
      close_quietly(connection.socket)
      @mutex.synchronize { @connections.delete(connection) }
      @logger.debug("Connection from #{peer} closed")
    end

    def mark_busy(connection, busy)
      @mutex.synchronize { connection.busy = busy }
    end

    def close_idle_connections
      @mutex.synchronize do
        @connections.each_value do |entry|
          connection = entry[:connection]
          close_quietly(connection.socket) unless connection.busy
        end
      end
    end

    def close_quietly(socket)
      socket.close unless socket.closed?
    rescue IOError, SystemCallError
      nil
    end

    def peer_name(socket)
      _family, port, _host, address = socket.peeraddr(false)
      "#{address}:#{port}"
    rescue IOError, SystemCallError
      'unknown peer'
    end
  end
end
