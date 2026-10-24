# Helper C: Transmits an isolated command between completion sentinels.
# A command may contain "exit", so evaluate it in a subshell to preserve the
# long-lived interactive shell and allow the status sentinel to run afterward.
private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
  wrapped_payload = "echo #{start_sentinel}; ( \n#{command_string}\n); echo #{end_sentinel}__$?__\n"
  write(wrapped_payload)
end
