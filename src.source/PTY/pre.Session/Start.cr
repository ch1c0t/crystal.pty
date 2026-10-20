# Starts the session. Overloaded to make streaming blocks completely optional.
def start(args : Array(String)? = nil, &block : String ->)
  start_session_engine(args, block)
end

def start(args : Array(String)? = nil)
  start_session_engine(args, nil)
end

include StartSessionEngine

include SpawnChild
include MonitorParentStream

include BeginBackgroundReader
include UpdateKernelTerminalDimensions
include PrepareEnvironmentVariables
