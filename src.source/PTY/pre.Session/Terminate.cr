def terminate : Nil
  # 1. Immediately toggle the active lifecycle flags locklessly
  @reader_active.set(false)

  # 2. Break the kernel read lock by forcefully closing the master I/O loop first
  if io = @master_io
    begin
      # Force raw unbuffered file descriptor closure to ensure immediate wake up
      io.close unless io.closed?
    rescue
    ensure
      @master_io = nil
    end
  end

  # 3. Give the background scheduler a brief microsecond slice to drop suspended fibers
  Fiber.yield

  # 4. Clean up and reap the child process handle without blocking deadlocks
  if proc = @process
    begin
      # Check if the process handle has already finished natively via the EOF cascade
      unless proc.terminated?
        proc.signal(Signal::TERM) rescue nil
        
        # Guard the wait call with a short non-blocking sleep retry matrix
        start_wait = Time.monotonic
        while !proc.terminated? && (Time.monotonic - start_wait) < 50.milliseconds
          Fiber.yield
        end
        
        # If it still resists, apply a terminal KILL strike
        if !proc.terminated?
          proc.signal(Signal::KILL) rescue nil
        end
      end
      
      # Final non-blocking reap to clear zombie states safely
      proc.wait rescue nil
    rescue
    ensure
      @process = nil
    end
  end
end
