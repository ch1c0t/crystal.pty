# Runs a one-shot shell command in a pseudo-terminal. The transcript combines stdout
# and stderr because both are attached to the same terminal.
def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  # Resolve nil values safely to match the strict Int32 constructor requirements
  session = Session.new(rows: rows || 24, columns: columns || 80)
  Command.new(command, session).execute_inside_pty(&stream_callback)
end

def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  session = Session.new(rows: rows || 24, columns: columns || 80)
  Command.new(command, session).execute_inside_pty
end

# Direct argv execution remains available through PTY.run without expanding
# PTY::Command beyond its shell-string API.
def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  # Step A: Instantiate the session engine explicitly
  session = Session.new(command.first, rows: rows || 24, columns: columns || 80)
  
  # Step B: Fire the background reader fiber loops using the provided argv context array
  session.start(command) do |chunk|
    stream_callback.call(chunk)
  end
  
  # Step C: Block the main process until execution wraps up
  exit_code = session.wait
  {session.output, exit_code}
end

def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  # Fix: Explicitly forward down to the block variant using a true yielding syntax 
  # to prevent infinite compiler recursion crashes
  run(command, rows: rows, columns: columns) do |_chunk|
    # Sink data cleanly
  end
end
