# Compatibility constructor used by tmux.run. The index and run_id remain part
# of the public API; each execution delegates to a Session using this status path.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
  @argv = nil
  @rows = nil
  @columns = nil
  @status_path = "/tmp/#{UUID.random}.pty_status"
end

def initialize(@raw_string : String)
  @argv = nil
  @rows = nil
  @columns = nil
  @status_path = "/tmp/#{UUID.random}.pty_status"
end

def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil)
  @argv = nil
  @rows = rows
  @columns = columns
  @status_path = "/tmp/#{UUID.random}.pty_status"
  validate_window_size
end

def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @raw_string = argv.join(" ")
  @rows = rows
  @columns = columns
  @status_path = "/tmp/#{UUID.random}.pty_status"
  validate_window_size
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
