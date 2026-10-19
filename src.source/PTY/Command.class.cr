getter raw_string : String
getter rows : Int32?
getter columns : Int32?

@argv : Array(String)?

include Initialize

def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
  session = if argv = @argv
              Session.new(argv, rows: @rows, columns: @columns)
            else
              Session.new(@raw_string, rows: @rows, columns: @columns)
            end
  session.start(&stream_callback)
  exit_code = session.wait
  {session.output, exit_code}
end

def execute_inside_pty : Tuple(String, Int32)
  execute_inside_pty { |_chunk| }
end
