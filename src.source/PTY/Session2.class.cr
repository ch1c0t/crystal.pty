getter raw_string : String
getter rows : Int32?
getter columns : Int32?
getter status_path : String
getter pid : Int32?
getter exit_code : Int32?

@argv : Array(String)?
@shell : String
@name : String
@cwd : String?
@env : Hash(String, String)?
@command : String?
@interactive_shell : Bool
@master_fd : Int32?
@master_io : IO::FileDescriptor?
@reader_done : Channel(Exception?)?
@output_buffer : IO::Memory
@started : Bool
@completed : Bool
@terminated : Bool
@reader_finished : Bool
@stream_error : Exception?

include Initialize
include Helpers
include Control
include Input
include Wait

def output : String
  @output_buffer.to_s
end
