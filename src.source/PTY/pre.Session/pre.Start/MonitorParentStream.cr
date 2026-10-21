private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, stream_callback : (String ->)?)
  IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close

  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  IO::FileDescriptor.set_blocking(master_fd, false)
  @master_io = master_io

  @reader_active = true

  spawn do
    io_buffer = Bytes.new(65536)

    # FIX WORKAROUND FOR CRYSTAL BUG #15011 / #17682:
    # Explicitly declare ALL variables here to force them into a safe local scope.
    # This prevents the compiler from throwing a KeyError during semantic mapping.
    bytes_read = 0
    chunk = ""
    proc = @process

    while !master_io.closed?
      begin
        bytes_read = master_io.read(io_buffer)
        if bytes_read == 0
          break
        end

        chunk = String.new(io_buffer[0, bytes_read])

        @mutex.synchronize do
          @output += chunk

          begin
            stream_callback.try(&.call(chunk))
          rescue ex : Exception
            @exception = ex

            # Re-fetch or use the pre-declared variable safely
            proc = @process
            if proc
              Process.signal(Signal::KILL, proc.pid) rescue nil
            end
            @reader_active = false
            @cond.broadcast
            break
          end

          @cond.broadcast 
        end
      rescue ex : IO::Error
        if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
          sleep(1.millisecond)
          next
        else
          break
        end
      end
    end

    @mutex.synchronize do
      @reader_active = false
      @cond.broadcast
    end
  end
end
