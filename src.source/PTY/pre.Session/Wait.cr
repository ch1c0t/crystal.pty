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
  pid = @pid.not_nil!
  loop do
    status = 0
    result = C.waitpid(pid, pointerof(status), 1)
    return decode_wait_status(status) if result == pid
    return 143 if @terminated && result < 0
    return 127 if result < 0

    unless @reader_finished
      select
      when error = @reader_done.not_nil!.receive
        @reader_finished = true
        @stream_error ||= error
        terminate_child_group(pid) if @stream_error
      when timeout(10.milliseconds)
      end
    else
      sleep(10.milliseconds)
    end
  end
end

private def decode_wait_status(status : Int32) : Int32
  signal = status & 0x7f
  signal == 0 ? (status >> 8) & 0xff : 128 + signal
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
