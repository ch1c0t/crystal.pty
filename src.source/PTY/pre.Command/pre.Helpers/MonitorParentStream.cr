# The status pipe is independent of the PTY stream, so a Crystal SIGCHLD handler
# cannot consume the child's status before the command runner sees it.
private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, status_read_fd : Int32, status_write_fd : Int32, pid : Int32, &stream_callback : String -> Nil) : Tuple(String, Int32)
  C.close(slave_fd)
  C.close(status_write_fd)
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  master_io.read_timeout = 50.milliseconds
  command_finished = Atomic(Bool).new(false)
  status_io = IO::FileDescriptor.new(status_read_fd, close_on_finalize: true)
  accumulated_buffer = IO::Memory.new
  stream_done = Channel(Exception?).new(1)
  status_done = Channel(Tuple(Int32?, Exception?)).new(1)

  spawn do
    stream_error : Exception? = nil
    begin
      io_buffer = Bytes.new(4096)
      finished_at : Time::Instant? = nil
      loop do
        if command_finished.get
          finished_at ||= Time.instant
          break if Time.instant - finished_at >= 250.milliseconds
        end
        begin
          bytes_read = master_io.read(io_buffer)
        rescue ex : IO::TimeoutError
          break if command_finished.get
          next
        end
        break if bytes_read <= 0
        chunk = String.new(io_buffer[0, bytes_read])
        accumulated_buffer.write(io_buffer[0, bytes_read])
        begin
          stream_callback.call(chunk)
        rescue ex
          stream_error = ex
          C.kill(-pid, 15)
          break
        end
      end
    rescue ex : IO::Error
      # Linux PTYs report EIO when the final slave descriptor closes.
    rescue ex
      stream_error = ex
      C.kill(-pid, 15)
    ensure
      stream_done.send(stream_error)
    end
  end

  spawn do
    exit_code : Int32? = nil
    status_error : Exception? = nil
    begin
      if line = status_io.gets
        exit_code = line.strip.to_i?
      end
    rescue ex
      status_error = ex
    ensure
      begin
        status_io.close
      rescue
      end
      status_done.send({exit_code, status_error})
    end
  end

  exit_code, status_error = status_done.receive
  command_finished.set(true)
  stream_error = stream_done.receive
  terminate_child_group(pid)
  raise stream_error if stream_error
  raise status_error if status_error

  {accumulated_buffer.to_s, exit_code || 127}
ensure
  master_io.try &.close
end
