private def begin_background_reader(stream_callback : (String ->)?)
  spawn do
    buffer = Bytes.new(4096)
    while (io = @master_io) && !io.closed?
      begin
        bytes_read = io.read(buffer)
        break if bytes_read == 0 # Clean End Of File (EOF)

        chunk = String.new(buffer[0, bytes_read])
        @output += chunk

        stream_callback.try(&.call(chunk))
        @channel.send(chunk)
      rescue IO::Error
        break # Handle closure signals gracefully
      end
    end
  end
end
