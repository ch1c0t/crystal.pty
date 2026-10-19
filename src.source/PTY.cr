@[Link("util")]
lib C
  struct WinSize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end

  fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : WinSize*) : Int32
  fun kill(pid : Int32, signal : Int32) : Int32
  fun close(fd : Int32) : Int32
end

# Runs a one-shot command in a pseudo-terminal. The transcript combines stdout
# and stderr because both are attached to the same terminal.
def self.run(command : String, *, rows : Int32 = 24, columns : Int32 = 80, &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
end

def self.run(command : Array(String), *, rows : Int32 = 24, columns : Int32 = 80, &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
end

def self.run(command : String, *, rows : Int32 = 24, columns : Int32 = 80) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty
end

def self.run(command : Array(String), *, rows : Int32 = 24, columns : Int32 = 80) : Tuple(String, Int32)
  Command.new(command, rows: rows, columns: columns).execute_inside_pty
end
