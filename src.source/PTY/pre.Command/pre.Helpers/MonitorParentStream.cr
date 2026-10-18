# Helper 3: Encapsulates async fiber creation, buffer logging, and blocking loops
private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, &stream_callback : String -> Nil) : Tuple(String, Int32)
  IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close
  
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  accumulated_buffer = IO::Memory.new
  stream_done = Channel(Nil).new

  # Fire background fiber for real-time unblocked read updates
  spawn do
    begin
      io_buffer = Bytes.new(4096)
      while (bytes_read = master_io.read(io_buffer)) > 0
        chunk = String.new(io_buffer[0, bytes_read])
        accumulated_buffer.write(io_buffer[0, bytes_read])
        stream_callback.call(chunk) # Stream directly to the block yield argument
      end
    rescue IO::Error
      # EIO safely caught when slave drops out
    ensure
      stream_done.send(nil)
    end
  end

  # Wait for process termination and ensure file tracking clears safely
  exit_code = wait_for_status_file
  stream_done.receive

  {accumulated_buffer.to_s, exit_code}
end
