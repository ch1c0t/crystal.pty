class TimeoutError < Exception
end

# Blocks cleanly using the zero-argument Sync::ConditionVariable API
def wait_for(target : String, timeout : Time::Span = 2.seconds)
  start_time = Time.instant 
  timed_out = false

  # Spawn a background timer fiber to break the condition wait if a timeout occurs
  spawn do
    sleep(timeout)
    @mutex.synchronize do
      timed_out = true
      @cond.broadcast # Wake up the waiting fiber below
    end
  end

  @mutex.synchronize do
    while !@output.includes?(target)
      if timed_out || start_time.elapsed > timeout
        raise Exception.new("Timed out waiting for '#{target}'")
      end

      # Blocks cleanly with 0% CPU usage until the reader fiber or the timer fiber signals a change
      @cond.wait
    end

    # Give the background loop one final slice to catch closely following bytes 
    # (like the stty size dimensions text flush) before returning to the test
    Fiber.yield
  end
end
