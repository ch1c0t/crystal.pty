getter raw_string : String
getter session : Session?

include Initialize

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  session = @session || create_and_start_session_with(stream_callback)

  exit_code = session.wait
  {session.output, exit_code}
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end

def create_session : Session
  if argv = @argv
    Session.new(argv)
  else
    Session.new(@raw_string)
  end
end

def create_and_start_session_with(stream_callback : String -> Nil) : Session
  session = create_session
  session.start(&stream_callback)
  session
end
