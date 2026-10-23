property rows : Int32
property columns : Int32

# Holds a raw pointer to the current immutable String heap object
@output_ptr : Atomic(Pointer(Void))

# Inherently thread-safe: Reads the atomic memory barrier instantly without a mutex
def output : String
  Box(String).unbox(@output_ptr.get)
end

@shell : String
@name : String?
@env : Hash(String, String)?
@cwd : String?

@process : Process?
@master_io : IO::FileDescriptor?
@exception : Exception? = nil
@reader_active : Atomic(Bool)
@active_run_callback : (String -> Nil)? = nil

@subscribers : Set(PTY::Queue(String))
@subscribers_mutex : Sync::Mutex

include Initialize
include Start
include Run
include AddQueue
include WaitFor
include Write
include Resize
include Terminate
