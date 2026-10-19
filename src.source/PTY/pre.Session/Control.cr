def start(&stream_callback : String -> Nil) : self
  start_with_callback(stream_callback)
end

def start : self
  start_with_callback(->(chunk : String) { nil })
end

private def start_with_callback(callback : Proc(String, Nil)) : self
  raise "PTY session has already been started" if @started

  master_fd, slave_fd = allocate_pty(@rows, @columns)
  child_pid = C.fork
  if child_pid < 0
    C.close(master_fd)
    C.close(slave_fd)
    raise "fork failed while starting PTY session"
  elsif child_pid == 0
    spawn_child(master_fd, slave_fd)
  end

  C.close(slave_fd)
  @pid = child_pid
  @master_fd = master_fd
  @master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  @reader_done = Channel(Exception?).new(1)
  @started = true
  spawn { read_output(callback) }
  self
end
