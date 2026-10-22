# Cleans up resources cleanly and forces blocking loops to break immediately
def terminate
  if process = @process
    Process.signal(Signal::KILL, process.pid) rescue nil
    process.wait rescue nil
    @process = nil
  end

  cleanup_streams
end

# Close the PTY handles to completely unblock the asynchronous read fiber loop
private def cleanup_streams
  @master_io.try(&.close)
  @master_io = nil
  @started.set(false)
end

def alive? : Bool
  if process = @process
    !process.exists? || process.terminated? ? false : true
  else
    false
  end
end

# Returns whether the pseudo-terminal descriptors have been booted
def started? : Bool
  @started.get
end
