class TimeoutError < Exception
end

# Blocks until the string is found in the output stream, or times out
def wait_for(target : String, timeout : Time::Span = 2.seconds)
  start_time = Time.instant 

  loop do
    if start_time.elapsed > timeout
      raise TimeoutError.new("Timed out waiting for '#{target}'")
    end

    return if @output.includes?(target)

    # Use non-blocking read to drain the stream channel quickly
    select
    when _chunk = @channel.receive?
      return if @output.includes?(target)
    else
      # Brief pause to yield to the reading fiber if the channel is empty
      sleep(5.milliseconds)
      return if @output.includes?(target)
    end
  end
end
