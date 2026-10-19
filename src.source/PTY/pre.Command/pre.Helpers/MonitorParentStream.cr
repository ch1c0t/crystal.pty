# Drain the PTY concurrently with Process#wait so verbose commands cannot
# deadlock against a full terminal buffer.
private def monitor_parent_stream(master_io : IO::FileDescriptor, process : Process, &stream_callback : String -> Nil) : Tuple(String, Int32)
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
          C.kill(-process.pid.to_i32, 15)
          break
        end
      end
    rescue ex : IO::Error
      # Linux PTYs commonly report EIO when the final slave closes.
    rescue ex
      stream_error = ex
      C.kill(-process.pid.to_i32, 15)
    ensure
      stream_done.send(stream_error)
    end
  end

  status : Process::Status? = nil
  wait_error : Exception? = nil
  begin
    status = process.wait
  rescue ex
    wait_error = ex
  ensure
    terminate_child_group(process.pid.to_i32)
  end

  stream_error = stream_done.receive
  raise wait_error if wait_error
  raise stream_error if stream_error
  child_status = status || raise("PTY child process completed without a status")

  exit_code = if child_status.normal_exit?
                child_status.exit_code
              elsif signal = child_status.exit_signal?
                128 + signal.value
              else
                1
              end
  {accumulated_buffer.to_s, exit_code}
ensure
  master_io.try &.close
end
