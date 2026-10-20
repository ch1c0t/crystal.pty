private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, stream_callback : (String ->)?)
  # Safely close slave copy in the parent process
  IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close

  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  @master_io = master_io

  spawn do
    begin
      io_buffer = Bytes.new(4096)
      # Keep reading as long as the master IO is open and active
      while !master_io.closed? && (bytes_read = master_io.read(io_buffer)) > 0
        chunk = String.new(io_buffer[0, bytes_read])
        @output += chunk

        stream_callback.try(&.call(chunk))

        # Use non-blocking channel send to avoid freezing the reader fiber
        select
        when @channel.send(chunk)
        else
          # If nothing is listening to the channel, move along smoothly
        end
      end
    rescue IO::Error
      # EIO or stream closure safely handled
    ensure
      @channel.close rescue nil
      @reader_done.send(nil) rescue nil
    end
  end
end
