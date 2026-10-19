def wait : Int32
  raise "PTY session has not been started" unless @started
  return @exit_code.not_nil! if @completed

  code = wait_for_status
  wait_for_reader
  @exit_code = code
  @completed = true
  raise @stream_error.not_nil! if @stream_error
  code
ensure
  cleanup_session if @completed
end

def terminate : Int32
  return @exit_code.not_nil! if @completed
  raise "PTY session has not been started" unless @started

  @terminated = true
  terminate_child_group(@pid.not_nil!)
  wait
end

def close : Int32
  terminate
end

private def wait_for_status : Int32
  loop do
    if code = read_status_file(@status_path)
      return code
    end

    if @reader_finished
      return 143 if @terminated || @stream_error
    else
      select
      when error = @reader_done.not_nil!.receive
        @reader_finished = true
        @stream_error ||= error
        if @stream_error
          terminate_child_group(@pid.not_nil!)
          return read_status_file(@status_path) || 143
        end
      when timeout(10.milliseconds)
      end
    end
    sleep(10.milliseconds) if @reader_finished && !@terminated && !@stream_error
  end
end

private def wait_for_reader : Nil
  return if @reader_finished

  select
  when error = @reader_done.not_nil!.receive
    @reader_finished = true
    @stream_error ||= error
  when timeout(2.seconds)
    terminate_child_group(@pid.not_nil!)
    error = @reader_done.not_nil!.receive
    @reader_finished = true
    @stream_error ||= error
  end
end

private def cleanup_session : Nil
  @master_io.try &.close
  @master_io = nil
  @master_fd = nil
  File.delete(@status_path) if File.exists?(@status_path)
  File.delete("#{@status_path}.tmp") if File.exists?("#{@status_path}.tmp")
  File.delete(@ready_path) if File.exists?(@ready_path)
  File.delete("#{@ready_path}.tmp") if File.exists?("#{@ready_path}.tmp")
end
