# Natively blocks until the child process and its inner commands completely exit
def wait : Int32
  if process = @process
    # Wait for the OS process to terminate first
    status = process.wait

    # Now that the process is dead, close the master stream to break the reader fiber loop
    cleanup_streams

    # Wait for the background stream reader fiber to process all incoming data
    @reader_done.receive?

    # If the background stream fiber caught a callback error, bubble it up now
    if ex = @exception
      @exception = nil # Reset state
      raise ex
    end

    status.exit_code
  else
    raise "Session context missing: process has not been started yet."
  end
end
