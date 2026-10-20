# Core interface adapter required by PTY::Command
def execute(command_string : String, stream_callback : (String -> Nil)?)
  # 1. Clear any old data if reusing the session instance
  @output = ""
  @channel = Channel(String).new
  @reader_done = Channel(Nil).new

  # 2. Start the interactive process context using our robust fork pipeline.
  # To run a raw shell string command natively inside an interactive subshell,
  # we forward it to the default shell binary using the standard -c execution flag.
  start_args = [@shell, "-c", command_string]
  
  if callback = stream_callback
    # Wrap the callback to bridge String -> Nil type compatibility safely
    start(start_args) do |chunk|
      callback.call(chunk)
    end
  else
    start(start_args)
  end
end

# Overload matching block-less execution requests
def execute(command_string : String)
  execute(command_string, nil)
end
