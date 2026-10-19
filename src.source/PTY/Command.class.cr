getter raw_string : String

@argv : Array(String)?

# Compatibility constructor used by tmux.run. Index/run_id were only used to
# name a temporary status file and are retained so existing callers keep working.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
  @argv = nil
end

def initialize(@raw_string : String)
  @argv = nil
end

# Preferred argv form avoids shell parsing and quoting problems.
def initialize(argv : Array(String))
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @raw_string = argv.join(" ")
end

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  master_fd, slave_fd = allocate_pty

  pid = C.fork
  if pid < 0
    C.close(master_fd)
    C.close(slave_fd)
    raise "fork failed while starting PTY command"
  elsif pid == 0
    spawn_child(master_fd, slave_fd)
  else
    monitor_parent_stream(master_fd, slave_fd, pid, &stream_callback)
  end
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end

include Helpers
