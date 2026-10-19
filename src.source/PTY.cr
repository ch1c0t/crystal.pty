@[Link("util")]
lib C
  fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
  fun login_tty(fd : Int32) : Int32
  fun fork : Int32
  fun _exit(status : Int32) : NoReturn
  fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
  fun kill(pid : Int32, signal : Int32) : Int32
  fun close(fd : Int32) : Int32
end

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
