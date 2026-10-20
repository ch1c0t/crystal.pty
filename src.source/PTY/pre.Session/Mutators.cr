# Feeds text commands natively to the child process's STDIN wire
def write(command : String)
  if io = @master_io
    io.write(command.to_slice)
    io.flush
  else
    raise "PTY pipeline unavailable: call #start first."
  end
end

# Resizes the ongoing active subshell terminal window on-the-fly
def resize(rows : Int32, columns : Int32)
  @rows = rows
  @columns = columns
  update_kernel_terminal_dimensions
end
