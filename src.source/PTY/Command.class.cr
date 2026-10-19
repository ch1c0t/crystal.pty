getter raw_string : String

@argv : Array(String)?

# Compatibility constructor used by tmux.run. The index and run_id are
# retained for source compatibility; status files are no longer created.
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
  master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
  slave_io = IO::FileDescriptor.new(slave_fd, close_on_finalize: true)

  begin
    process = launch_process(slave_io)
  ensure
    slave_io.close
  end

  monitor_parent_stream(master_io, process, &stream_callback)
rescue ex
  master_io.try &.close
  slave_io.try &.close
  raise ex
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end

include Helpers
