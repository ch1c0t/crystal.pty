lib C
  fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
  fun kill(pid : Int32, signal : Int32) : Int32
  fun close(fd : Int32) : Int32
end
