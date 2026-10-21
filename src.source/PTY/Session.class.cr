property rows : Int32
property columns : Int32
getter output : String = ""

@shell : String
@name : String?
@env : Hash(String, String)?
@cwd : String?

@process : Process?
@master_io : IO::FileDescriptor?
@exception : Exception? = nil
@reader_active = true

@mutex : Sync::Mutex
@cond : Sync::ConditionVariable
@active_run_callback : (String -> Nil)? = nil

include Initialize
include Run
include Start
include Execute
include Wait
include WaitFor
include Terminate
include Write
include Resize
