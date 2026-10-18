getter raw_string : String
getter status_path : String

def initialize(@raw_string, index : Int32, run_id : Int64)
  @status_path = "/tmp/#{UUID.random}.pty_status_#{run_id}_#{index}.txt"
end

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  master_fd, slave_fd = allocate_pty

  pid = C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # Inside the Child Process sandbox
    spawn_child(slave_fd)
  else
    # Inside the Parent Process proxy monitor
    monitor_parent_stream(master_fd, slave_fd, &stream_callback)
  end
end

include Helpers
