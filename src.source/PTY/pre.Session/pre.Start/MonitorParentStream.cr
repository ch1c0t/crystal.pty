private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, stream_callback : (String ->)?)
  IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close

  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  IO::FileDescriptor.set_blocking(master_fd, false)
  @master_io = master_io

  @reader_active = true

  spawn do
    io_buffer = Bytes.new(4096)
    while !master_io.closed?
      begin
        bytes_read = master_io.read(io_buffer)
        if bytes_read == 0
          break
        end

        chunk = String.new(io_buffer[0, bytes_read])

        # Synchronize updates tightly to prevent memory race states
        @mutex.synchronize do
          @output += chunk

          begin
            stream_callback.try(&.call(chunk))
          rescue ex : Exception
            @exception = ex
            if proc = @process
              Process.signal(Signal::KILL, proc.pid) rescue nil
            end
            @reader_active = false
            @cond.broadcast # Alert all waiting threads to exit/throw immediately
            break
          end

          # Wakes up any active `wait_for` listeners instantly
          @cond.broadcast 
        end
      rescue ex : IO::Error
        if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
          Fiber.yield
          next
        else
          break
        end
      end
    end

    @mutex.synchronize do
      @reader_active = false
      @cond.broadcast # Final wrap broadcast unblocks `.wait` checkpoints
    end
  end
end
