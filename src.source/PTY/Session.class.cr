property rows : Int32
property columns : Int32
getter output : String = ""

@shell : String
@name : String?
@env : Hash(String, String)?
@cwd : String?

@process : Process?
@master_io : IO::FileDescriptor?
@channel = Channel(String).new
@reader_done = Channel(Nil).new

include Initialize
include Start
include Wait
include WaitFor
include Terminate
include Mutators
