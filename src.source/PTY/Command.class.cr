getter raw_string : String
getter session : Session

include Initialize

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  @session.execute(@raw_string, stream_callback)
  exit_code = @session.wait
  {@session.output, exit_code}
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end
