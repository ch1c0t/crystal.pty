getter raw_string : String
getter session : Session

include Initialize

alias Output = String
alias ExitCode = Int32

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(Output, ExitCode)
  # 1. Execute the string script natively over the interactive wire pipeline
  result = @session.run(@raw_string, &stream_callback)
  
  # 2. Only terminate the session if this specific command created it natively
  if @owns_session
    @session.terminate
  end

  {result.output, result.status}
end

def execute_inside_pty : Tuple(Output, ExitCode)
  execute_inside_pty { |_chunk| }
end
