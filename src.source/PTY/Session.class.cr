property rows : Int32
property columns : Int32
getter output : String = ""

@shell : String
@name : String?
@env : Hash(String, String)?
@cwd : String?

@process : Process?
@master_io : IO::FileDescriptor?

@mutex : Sync::Mutex
@cond : Sync::ConditionVariable
@exception : Exception? = nil
@reader_active = true

include Initialize
include Start
include Execute
include Wait
include WaitFor
include Terminate
include Mutators
