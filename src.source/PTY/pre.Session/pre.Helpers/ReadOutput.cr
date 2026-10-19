private def read_output(callback : Proc(String, Nil)) : Nil
  error : Exception? = nil
  io_buffer = Bytes.new(4096)

  begin
    loop do
      bytes_read = begin
        @master_io.not_nil!.read(io_buffer)
      rescue ex : IO::Error
        break
      end
      break if bytes_read <= 0

      chunk = String.new(io_buffer[0, bytes_read])
      @output_buffer.write(io_buffer[0, bytes_read])
      begin
        callback.call(chunk)
      rescue ex
        error = ex
        terminate_child_group(@pid.not_nil!)
        break
      end
    end
  rescue ex
    error = ex
    terminate_child_group(@pid.not_nil!)
  ensure
    @stream_error = error
    @reader_done.not_nil!.send(error)
  end
end
