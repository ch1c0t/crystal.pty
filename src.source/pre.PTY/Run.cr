# Runs a one-shot shell command in a pseudo-terminal. The transcript combines stdout
# and stderr because both are attached to the same terminal.
def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  session = Session.new(command, rows: rows, columns: columns)
  Command.new(command, session).execute_inside_pty(&stream_callback)
end

def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  session = Session.new(command, rows: rows, columns: columns)
  Command.new(command, session).execute_inside_pty
end

# Direct argv execution remains available through PTY.run without expanding
# PTY::Command beyond its shell-string API.
def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  session = Session.new(command, rows: rows, columns: columns).start(&stream_callback)
  exit_code = session.wait
  {session.output, exit_code}
end

def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  run(command, rows: rows, columns: columns) { |_chunk| }
end
