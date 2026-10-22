# Helper C: Transmits the text sandwich straight down the interactive line
private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
  write("echo #{start_sentinel}\n")
  write("#{command_string}\n") unless command_string.empty?
  write("echo #{end_sentinel}__$?__\n")
end
