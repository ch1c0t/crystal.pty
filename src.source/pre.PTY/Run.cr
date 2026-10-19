# Runs a one-shot command in a pseudo-terminal. The transcript combines stdout
# and stderr because both are attached to the same terminal.
def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
end

def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
end

def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty
end

def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty
end
