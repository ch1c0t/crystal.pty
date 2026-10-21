class TimeoutError < Exception
end

# Blocks cleanly and ensures no background fiber broadcasts are ever missed
def wait_for(target : String, timeout : Time::Span = 2.seconds)
  start_time = Time.instant 

  @mutex.synchronize do
    # 1. Loop continuously until the string manifests or time runs out
    while !@output.includes?(target)
      if start_time.elapsed > timeout
        raise TimeoutError.new("Timed out waiting for '#{target}'")
      end

      # Instantly raise the callback error if one was registered in the background
      p "in #wait_for, before exin"
      if ex = @exception
        p "#{ex} in #wait_for, in ex"
        @exception = nil
        raise ex
      end

      # 2. Release the mutex lock briefly to let the background reader fiber 
      # write text chunks, and sleep for a tiny slice to yield priority.
      @mutex.unlock
      begin
        sleep(5.milliseconds)
      ensure
        # 3. Automatically re-acquire the lock safely before checking the loop condition again
        @mutex.lock
      end
    end
    
    # =======================================================================
    # THE ABSOLUTE GATE CHECK (FIXES THE BYPASS RACE CONDITION)
    # =======================================================================
    # If the loop exited because the target was found, but the background fiber 
    # encountered a callback exception on that exact chunk step, we must 
    # prioritize raising the error over a clean return!
    if ex = @exception
      @exception = nil
      raise ex
    end

    # 4. Give the reader loop one final tiny slice to let closely trailing characters settle
    Fiber.yield
  end
end
