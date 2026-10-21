# Blocks the main execution thread cleanly until the process finishes running
def wait : Int32
  if process = @process
    # Wait for the OS status to toggle natively
    status = process.wait
    cleanup_streams

    # Block efficiently until the reader loop finishes flushing remaining buffers
    @mutex.synchronize do
      while @reader_active
        @cond.wait
      end

      # Propagate asynchronous callback errors safely if caught
      if ex = @exception
        @exception = nil
        raise ex
      end
    end

    status.exit_code
  else
    raise "Session context missing: process has not been started yet."
  end
end
