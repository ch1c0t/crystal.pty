# Close the parent's copy of the slave and drain the master concurrently with
# waitpid, preventing verbose commands from blocking on a full terminal buffer.
private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, pid : Int32, &stream_callback : String -> Nil) : Tuple(String, Int32)
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
  wait_error : Exception? = nil
  begin
    exit_code = wait_for_child(pid)
  rescue ex
    wait_error = ex
  ensure
    terminate_child_group(pid)
  end

  stream_error = stream_done.receive
  raise wait_error if wait_error
  raise stream_error if stream_error
  {accumulated_buffer.to_s, exit_code || 1}
ensure
  master_io.try &.close
end
