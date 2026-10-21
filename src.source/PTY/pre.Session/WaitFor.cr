class TimeoutError < Exception
end

# Blocks efficiently without wasting CPU loops until the target string arrives
def wait_for(target : String, timeout : Time::Span = 2.seconds)
  start_time = Time.instant 

  @mutex.synchronize do
    # Loop safely manages spurious wakeups and tracks time limits dynamically
    while !@output.includes?(target)
      remaining = timeout - start_time.elapsed
      if remaining <= Time::Span::ZERO
        raise TimeoutError.new("Timed out waiting for '#{target}'")
      end

      # Blocks cleanly; instantly releases the lock so the reader fiber can write text,
      # then re-acquires the lock automatically the millisecond it gets signaled.
      @cond.wait(@mutex, remaining)
    end
  end
end
