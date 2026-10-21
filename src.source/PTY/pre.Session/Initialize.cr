def initialize(
  @shell : String = "/bin/sh",
  *,
  @rows : Int32 = 24,
  @columns : Int32 = 80,
  @name : String? = nil,
  @env : Hash(String, String)? = nil,
  @cwd : String? = nil
)
  @mutex = Sync::Mutex.new
  @cond = Sync::ConditionVariable.new(@mutex)
end

def initialize(
  *,
  @rows : Int32,
  @columns : Int32,
  @shell : String = "/bin/sh",
  @name : String? = nil,
  @env : Hash(String, String)? = nil,
  @cwd : String? = nil
)
  @mutex = Sync::Mutex.new
  @cond = Sync::ConditionVariable.new(@mutex)
end
