def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil, status_path : String? = nil)
  @argv = nil
  @rows = rows
  @columns = columns
  @status_path = status_path || "/tmp/#{UUID.random}.pty_status"
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

def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, status_path : String? = nil)
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @raw_string = argv.join(" ")
  @rows = rows
  @columns = columns
  @status_path = status_path || "/tmp/#{UUID.random}.pty_status"
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
