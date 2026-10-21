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
