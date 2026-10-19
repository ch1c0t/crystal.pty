# One-shot runner for argv or shell commands.
def self.run(command : String, &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command).execute_inside_pty(&stream_callback)
end

def self.run(command : Array(String), &stream_callback : String -> Nil) : Tuple(String, Int32)
  Command.new(command).execute_inside_pty(&stream_callback)
end

def self.run(command : String) : Tuple(String, Int32)
  Command.new(command).execute_inside_pty
end

def self.run(command : Array(String)) : Tuple(String, Int32)
  Command.new(command).execute_inside_pty
end
