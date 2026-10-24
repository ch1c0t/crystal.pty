# Helper C: Transmits the text sandwich straight down the interactive line
private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
  # Run in a subshell so an "exit" command doesn't kill the persistent shell.
  wrapped_payload = "echo #{start_sentinel}; ( \n#{command_string}\n); echo #{end_sentinel}__$?__\n"
  write(wrapped_payload)
end
