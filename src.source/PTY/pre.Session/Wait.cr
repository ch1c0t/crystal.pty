# Natively blocks until the child process and its inner commands completely exit
def wait : Int32
  if process = @process
    # Wait for the OS process to terminate first
    status = process.wait

    # Drain buffered output through EOF before closing the master stream.
    @reader_done.receive?
    cleanup_streams

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
