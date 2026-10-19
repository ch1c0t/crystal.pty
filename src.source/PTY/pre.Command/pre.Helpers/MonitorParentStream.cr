# Drain PTY output with a blocking reader while waiting for command completion.
# The status file provides command status; PTY EOF remains the stream's end condition.
private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, pid : Int32, status_path : String, &stream_callback : String -> Nil) : Tuple(String, Int32)
  C.close(slave_fd)
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  accumulated_buffer = IO::Memory.new
  stream_done = Channel(Exception?).new(1)

  spawn do
    stream_error : Exception? = nil
    begin
      io_buffer = Bytes.new(4096)
      while (bytes_read = master_io.read(io_buffer)) > 0
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

  exit_code : Int32? = nil
  stream_error : Exception? = nil
  stream_finished = false

  loop do
    if code = read_status_file(status_path)
      exit_code = code
      break
    end

    select
    when stream_error = stream_done.receive
      stream_finished = true
      if stream_error
        terminate_child_group(pid)
        raise stream_error
      end
      exit_code = read_status_file(status_path) || 127
      break
    after 10.milliseconds
    end
  end

  unless stream_finished
    select
    when stream_error = stream_done.receive
      stream_finished = true
    after 2.seconds
      # Only use process-group cleanup if descendants keep the slave open.
      terminate_child_group(pid)
      stream_error = stream_done.receive
      stream_finished = true
    end
  end

  terminate_child_group(pid) unless stream_finished
  raise stream_error if stream_error

  {accumulated_buffer.to_s, exit_code || 127}
ensure
  master_io.try &.close
  File.delete(status_path) if File.exists?(status_path)
  File.delete("#{status_path}.tmp") if File.exists?("#{status_path}.tmp")
end
