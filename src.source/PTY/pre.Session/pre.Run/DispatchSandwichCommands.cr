# Helper C: Transmits the text sandwich straight down the interactive line
private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
  write("echo #{start_sentinel}\n")
  write("#{command_string}\n")
  # write("#{command_string}\n") unless command_string.empty?
  write("echo #{end_sentinel}__$?__\n")
end
# Inside the DispatchSandwichCommands helper module:
# def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
#   # FIX: Group the command execution within an isolated syntax frame, 
#   # ensuring inner instructions cannot accidentally swallow trailing control sentinels
#   wrapped_payload = "echo #{start_sentinel}; ( #{command_string} ); echo #{end_sentinel}__$?__\n"
#   write(wrapped_payload)
# end
