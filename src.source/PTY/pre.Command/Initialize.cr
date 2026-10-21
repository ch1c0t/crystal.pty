@session : PTY::Session
@owns_session : Bool

# Constructor A: Command creates its own session instance
def initialize(@raw_string : String)
  session = Session.new
  session.start # Fire up the interactive subshell thread pool
  @session = session
  @owns_session = true # Mark that this instance handles its own cleanup
end

# Constructor B: Command adopts a pre-existing session context shared by others
def initialize(@raw_string : String, @session : PTY::Session)
  @owns_session = false # Do not kill this session; someone else is managing it
end
