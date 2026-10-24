private def spawn_ingestion_loop
  spawn do
    io_buffer = Bytes.new(65536)
    master_io = @master_io.not_nil!

    loop do
      break if master_io.closed?
      begin
        bytes_read = master_io.read(io_buffer)
        break if bytes_read == 0

        # Move the data instantly into our thread-safe queue
        chunk = String.new(io_buffer[0, bytes_read])

        p "in #spawn_ingestion_loop"
        debug_log("Ingestion Fiber Received Data", {
          bytes_read: bytes_read,
          raw_payload: chunk
        })

        @ingest_queue.push(chunk)
      rescue ex : IO::Error
        # Handle non-blocking retry signs gracefully
        if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
          # EMIT: Push a special in-band token to @ingest_queue signifying 
          # that the OS kernel buffer is temporarily empty (idle).
          @ingest_queue.push(:stream_idle)
          Fiber.yield
          sleep(1.millisecond)
          next
        else
          break
        end
      end
    end
    @reader_active.set(false)
    @ingest_queue.close # ◄─ Signal completion to the consumer layer
  end
end
