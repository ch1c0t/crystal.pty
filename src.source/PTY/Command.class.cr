getter raw_string : String
getter rows : Int32?
getter columns : Int32?

@argv : Array(String)?

# Compatibility constructor used by tmux.run. The index and run_id remain part
# of the API; child status is reported through a private pipe.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64, *, rows : Int32? = nil, columns : Int32? = nil)
  @argv = nil
  @rows = rows
  @columns = columns
  validate_window_size
end

def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil)
  @argv = nil
  @rows = rows
  @columns = columns
  validate_window_size
end

# Prefer argv when shell parsing is not required.
def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @raw_string = argv.join(" ")
  @rows = rows
  @columns = columns
  validate_window_size
end

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  master_fd, slave_fd = allocate_pty(@rows, @columns)
  pipe_fds = StaticArray(Int32, 2).new(0)

  if LibC.pipe(pipe_fds) == -1
    C.close(master_fd)
    C.close(slave_fd)
    raise "pipe failed while starting PTY command"
  end

  status_read_fd = pipe_fds[0]
  status_write_fd = pipe_fds[1]
  pid = C.fork

  if pid < 0
    C.close(master_fd)
    C.close(slave_fd)
    C.close(status_read_fd)
    C.close(status_write_fd)
    raise "fork failed while starting PTY command"
  elsif pid == 0
    spawn_child(master_fd, slave_fd, status_read_fd, status_write_fd)
  else
    monitor_parent_stream(master_fd, slave_fd, status_read_fd, status_write_fd, pid, &stream_callback)
  end
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end

private def validate_window_size : Nil
  if @rows.nil? != @columns.nil?
    raise ArgumentError.new("PTY rows and columns must be provided together")
  end

  if rows = @rows
    raise ArgumentError.new("PTY rows must be between 1 and 65535") if rows < 1 || rows > 65_535
  end
  if columns = @columns
    raise ArgumentError.new("PTY columns must be between 1 and 65535") if columns < 1 || columns > 65_535
  end
end

include Helpers
