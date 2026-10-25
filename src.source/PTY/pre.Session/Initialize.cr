def initialize(
  shell : String | Symbol = "/bin/sh",
  *,
  @rows : Int32 = 24,
  @columns : Int32 = 80,
  @name : String? = nil,
  @env : Hash(String, String)? = nil,
  @cwd : String? = nil
)
  @shell = validated_shell(shell)
  initialize_state
end

def initialize(
  *,
  @rows : Int32,
  @columns : Int32,
  shell : String | Symbol = "/bin/sh",
  @name : String? = nil,
  @env : Hash(String, String)? = nil,
  @cwd : String? = nil
)
  @shell = validated_shell(shell)
  initialize_state
end

private def initialize_state
  @started = Atomic(Bool).new(false)
  @ingest_queue = PTY::Queue(String | Symbol).new
  @subscribers = Set(PTY::Queue(String | Symbol)).new
  @subscribers_mutex = Sync::Mutex.new

  # Securely box the initial empty string state into a raw atomic pointer reference
  @output_ptr = Atomic(Pointer(Void)).new(Box(String).box(""))
  @reader_active = Atomic(Bool).new(false)
end

private def validated_shell(shell : String | Symbol) : String
  candidate = case shell
              when String
                shell
              when Symbol
                case shell
                when :sh, :bash, :zsh, :fish, :dash, :ksh, :csh, :tcsh
                  shell.to_s
                else
                  raise ArgumentError.new("Unknown PTY shell symbol: #{shell.inspect}")
                end
              end

  process_env = ENV.to_h
  process_env.merge!(@env) if @env
  search_path = process_env["PATH"]? || "/usr/bin:/bin"
  unless Process.find_executable(candidate, search_path, @cwd || Dir.current)
    raise ArgumentError.new("PTY shell must resolve to an executable path; got #{shell.inspect}")
  end

  candidate
end