def initialize(
  shell : String = (ENV["SHELL"]? || "/bin/sh"),
  *,
  name : String = "xterm-256color",
  rows : Int32? = nil,
  columns : Int32? = nil,
  cwd : String? = nil,
  env : Hash(String, String)? = nil
)
  raise ArgumentError.new("PTY shell must not be empty") if shell.empty?
  @shell = shell
  @name = name
  @cwd = cwd
  @env = env
  @raw_string = ""
  @argv = nil
  @command = nil
  @interactive_shell = true
  @rows = rows
  @columns = columns
  initialize_state(rows, columns)
end

# Direct argv execution remains supported by PTY.run(Array(String)).
def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @shell = ENV["SHELL"]? || "/bin/sh"
  @name = "xterm-256color"
  @cwd = nil
  @env = nil
  @command = nil
  @interactive_shell = false
  @raw_string = argv.join(" ")
  @rows = rows
  @columns = columns
  initialize_state(rows, columns)
end

private def initialize_state(rows : Int32?, columns : Int32?) : Nil
  @status_path = "/tmp/#{UUID.random}.pty_status"
  @ready_path = "#{@status_path}.ready"
  @pid = nil
  @exit_code = nil
  @master_fd = nil
  @master_io = nil
  @reader_done = nil
  @output_buffer = IO::Memory.new
  @started = false
  @completed = false
  @terminated = false
  @reader_finished = false
  @stream_error = nil
  validate_dimensions(rows, columns)
end

private def validate_dimensions(rows : Int32?, columns : Int32?) : Nil
  if rows.nil? != columns.nil?
    raise ArgumentError.new("PTY rows and columns must be provided together")
  end
  if rows && (rows < 1 || rows > 65_535)
    raise ArgumentError.new("PTY rows must be between 1 and 65535")
  end
  if columns && (columns < 1 || columns > 65_535)
    raise ArgumentError.new("PTY columns must be between 1 and 65535")
  end
end
