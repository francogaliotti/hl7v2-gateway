# frozen_string_literal: true

require 'io/wait'

module Hl7Gateway
  # Minimal Lower Layer Protocol: <VT> payload <FS><CR>.
  module MLLP
    START_BLOCK = "\x0B".b.freeze
    END_BLOCK = "\x1C".b.freeze
    CARRIAGE_RETURN = "\r".b.freeze

    module_function

    def frame(payload)
      START_BLOCK + payload.to_s.b + END_BLOCK + CARRIAGE_RETURN
    end

    # Extracts the payload of a single framed message. Bytes outside the frame are ignored.
    def unframe(data)
      bytes = data.to_s.b
      start = bytes.index(START_BLOCK)
      finish = start && bytes.index(END_BLOCK, start + 1)
      raise FramingError, 'Data is not wrapped in an MLLP frame' unless finish

      bytes[(start + 1)...finish]
    end

    # Reads successive MLLP frames from a socket (or any IO that supports wait_readable).
    #
    # The reader is forgiving about noise between frames, and about a missing <CR> after the
    # end block, but strict about size limits and truncated messages.
    class Stream
      CHUNK_SIZE = 4096

      def initialize(io, max_bytes:, idle_timeout:)
        @io = io
        @max_bytes = max_bytes
        @idle_timeout = idle_timeout
        @buffer = String.new(encoding: Encoding::BINARY)
      end

      # Returns the next payload, or nil when the peer closed the connection (or stayed idle)
      # between two messages.
      def read_message
        loop do
          payload = extract_payload
          return payload if payload

          raise FramingError, "Message exceeds #{@max_bytes} bytes" if @buffer.bytesize > @max_bytes
          return nil unless fill_buffer
        end
      end

      private

      def extract_payload
        start = @buffer.index(START_BLOCK)
        if start.nil?
          @buffer.clear
          return nil
        end

        finish = @buffer.index(END_BLOCK, start + 1)
        return nil unless finish

        payload = @buffer[(start + 1)...finish]
        @buffer = @buffer[(finish + 1)..] || String.new(encoding: Encoding::BINARY)
        @buffer = @buffer.delete_prefix(CARRIAGE_RETURN)
        payload
      end

      # Returns false when there is nothing left to read.
      def fill_buffer
        loop do
          chunk = @io.read_nonblock(CHUNK_SIZE, exception: false)
          case chunk
          when nil then return end_of_stream
          when :wait_readable then return false unless data_available?
          else
            @buffer << chunk
            return true
          end
        end
      end

      def data_available?
        # wait_readable (unlike IO.select) is interrupted when another thread closes the socket.
        return true if @io.wait_readable(@idle_timeout)

        raise FramingError, 'Timed out waiting for the end of the message' if @buffer.include?(START_BLOCK)

        false
      end

      # The peer hung up: fine between messages, an error in the middle of one.
      def end_of_stream
        raise FramingError, 'Connection closed in the middle of a message' if @buffer.include?(START_BLOCK)
      end
    end
  end
end
