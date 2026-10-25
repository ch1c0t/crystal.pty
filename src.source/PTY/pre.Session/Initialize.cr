def initialize(
  shell : (String | Symbol)? = nil,
  *,
  @rows : Int32 = 24,
  @columns : Int32 = 80,
  @name : String? = nil,
  @env : Hash(String, String)? = nil,
  @cwd : String? = nil
)
  @shell = validated_shell(shell)
  @started = Atomic(Bool).new(false)
  @ingest_queue = PTY::Queue(String | Symbol).new
  @subscribers = Set(PTY::Queue(String | Symbol)).new
  @subscribers_mutex = Sync::Mutex.new

  # Securely box the initial empty string state into a raw atomic pointer reference
  @output_ptr = Atomic(Pointer(Void)).new(Box(String).box(""))
  @reader_active = Atomic(Bool).new(false)
end

include ValidatedShell
