getter raw_string : String
getter rows : Int32
getter columns : Int32

@argv : Array(String)?

# Compatibility constructor used by tmux.run. The index and run_id remain part
# of the public signature, but no status files are created.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64, *, rows : Int32 = 24, columns : Int32 = 80)
  @argv = nil
  @rows = rows
  @columns = columns
  validate_window_size
end

def initialize(@raw_string : String, *, rows : Int32 = 24, columns : Int32 = 80)
  @argv = nil
  @rows = rows
  @columns = columns
  validate_window_size
end

# Prefer argv when shell parsing is not required.
def initialize(argv : Array(String), *, rows : Int32 = 24, columns : Int32 = 80)
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
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  slave_io = IO::FileDescriptor.new(slave_fd, close_on_finalize: true)

  process = begin
    launch_process(slave_io)
  rescue ex
    master_io.close
    raise ex
  ensure
    slave_io.close
  end

  monitor_parent_stream(master_io, process, &stream_callback)
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end

private def validate_window_size : Nil
  if @rows < 1 || @rows > 65_535
    raise ArgumentError.new("PTY rows must be between 1 and 65535")
  end
  if @columns < 1 || @columns > 65_535
    raise ArgumentError.new("PTY columns must be between 1 and 65535")
  end
end

include Helpers
