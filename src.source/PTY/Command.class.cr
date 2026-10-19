getter raw_string : String
getter rows : Int32?
getter columns : Int32?
getter status_path : String

@argv : Array(String)?

include Initialize
include Helpers

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  master_fd, slave_fd = allocate_pty(@rows, @columns)
  pid = C.fork

  if pid < 0
    C.close(master_fd)
    C.close(slave_fd)
    raise "fork failed while starting PTY command"
  elsif pid == 0
    spawn_child(master_fd, slave_fd)
  else
    monitor_parent_stream(master_fd, slave_fd, pid, @status_path, &stream_callback)
  end
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end
