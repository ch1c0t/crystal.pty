# Feeds text commands natively to the child process's STDIN wire
def write(command : String)
  if io = @master_io
    io.write(command.to_slice)
    io.flush
  else
    raise "PTY pipeline unavailable: call #start first."
  end
end
