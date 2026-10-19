# Compatibility constructor used by tmux.run. The index and run_id remain part
# of the public API; each execution delegates to a Session.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
end

def initialize(@raw_string : String, @session : Session? = nil)
end

def initialize(argv : Array(String), @session : Session? = nil)
  raise ArgumentError.new("PTY command must not be empty") if argv.empty?
  raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

  @argv = argv.dup
  @raw_string = argv.join(" ")
end

@argv : (Array(String))?
