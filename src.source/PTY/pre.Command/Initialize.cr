# Compatibility constructor used by tmux.run. The index and run_id remain part
# of the public API; each execution delegates to a Session.
def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
  @session = Session.new
end

def initialize(@raw_string : String, @session : Session = Session.new)
end
