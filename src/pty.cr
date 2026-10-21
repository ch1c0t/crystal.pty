require "uuid"
require "sync/mutex"
require "sync/condition_variable"

module PTY
  lib C
    struct WinSize
      ws_row : UInt16
      ws_col : UInt16
      ws_xpixel : UInt16
      ws_ypixel : UInt16
    end
    
    fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
    fun login_tty(fd : Int32) : Int32
    fun fork : Int32
    fun _exit(status : Int32) : NoReturn
    fun close(fd : Int32) : Int32
    fun ioctl(fd : Int32, request : UInt64, argp : Void*) : Int32
  end

  module Run
    # Runs a one-shot shell command in a pseudo-terminal. The transcript combines stdout
    # and stderr because both are attached to the same terminal.
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      # Resolve nil values safely to match the strict Int32 constructor requirements
      session = Session.new(rows: rows || 24, columns: columns || 80)
      Command.new(command, session).execute_inside_pty(&stream_callback)
    end
    
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      session = Session.new(rows: rows || 24, columns: columns || 80)
      Command.new(command, session).execute_inside_pty
    end
    
    # Direct argv execution remains available through PTY.run without expanding
    # PTY::Command beyond its shell-string API.
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      # Step A: Instantiate the session engine explicitly
      session = Session.new(command.first, rows: rows || 24, columns: columns || 80)
      
      # Step B: Fire the background reader fiber loops using the provided argv context array
      session.start(command) do |chunk|
        stream_callback.call(chunk)
      end
      
      # Step C: Block the main process until execution wraps up
      exit_code = session.wait
      {session.output, exit_code}
    end
    
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      # Fix: Explicitly forward down to the block variant using a true yielding syntax 
      # to prevent infinite compiler recursion crashes
      run(command, rows: rows, columns: columns) do |_chunk|
        # Sink data cleanly
      end
    end
  end

  extend Run

  class Command
    module Initialize
      def initialize(@raw_string : String)
        @session = Session.new
      end
      
      def initialize(@raw_string : String, @session : Session)
      end
    end
  
    getter raw_string : String
    getter session : Session
    
    include Initialize
    
    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
      @session.execute(@raw_string, stream_callback)
      exit_code = @session.wait
      {@session.output, exit_code}
    end
    
    def execute_inside_pty : Tuple(String, Int32)
      execute_inside_pty { |_chunk| }
    end
  end

  class Session
    module Execute
      # Core interface adapter required by PTY::Command
      def execute(command_string : String, stream_callback : (String -> Nil)?)
        # 1. Clear any old data if reusing the session instance
        @output = ""
        @channel = Channel(String).new
        @reader_done = Channel(Nil).new
      
        # 2. Start the interactive process context using our robust fork pipeline.
        # To run a raw shell string command natively inside an interactive subshell,
        # we forward it to the default shell binary using the standard -c execution flag.
        start_args = [@shell, "-c", command_string]
        
        if callback = stream_callback
          # Wrap the callback to bridge String -> Nil type compatibility safely
          start(start_args) do |chunk|
            callback.call(chunk)
          end
        else
          start(start_args)
        end
      end
      
      # Overload matching block-less execution requests
      def execute(command_string : String)
        execute(command_string, nil)
      end
    end
  
    module Initialize
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
    end
  
    module Mutators
      # Feeds text commands natively to the child process's STDIN wire
      def write(command : String)
        if io = @master_io
          io.write(command.to_slice)
          io.flush
        else
          raise "PTY pipeline unavailable: call #start first."
        end
      end
      
      # Resizes the ongoing active subshell terminal window on-the-fly
      def resize(rows : Int32, columns : Int32)
        @rows = rows
        @columns = columns
        update_kernel_terminal_dimensions
      end
    end
  
    module Start
      module MonitorParentStream
        private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, stream_callback : (String ->)?)
          IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close
        
          master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
          IO::FileDescriptor.set_blocking(master_fd, false)
          @master_io = master_io
        
          @reader_active = true
        
          spawn do
            io_buffer = Bytes.new(4096)
            while !master_io.closed?
              begin
                bytes_read = master_io.read(io_buffer)
                if bytes_read == 0
                  break
                end
        
                chunk = String.new(io_buffer[0, bytes_read])
        
                # Synchronize updates tightly to prevent memory race states
                @mutex.synchronize do
                  @output += chunk
        
                  begin
                    stream_callback.try(&.call(chunk))
                  rescue ex : Exception
                    @exception = ex
                    if proc = @process
                      Process.signal(Signal::KILL, proc.pid) rescue nil
                    end
                    @reader_active = false
                    @cond.broadcast # Alert all waiting threads to exit/throw immediately
                    break
                  end
        
                  # Wakes up any active `wait_for` listeners instantly
                  @cond.broadcast 
                end
              rescue ex : IO::Error
                if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
                  Fiber.yield
                  next
                else
                  break
                end
              end
            end
        
            @mutex.synchronize do
              @reader_active = false
              @cond.broadcast # Final wrap broadcast unblocks `.wait` checkpoints
            end
          end
        end
      end
    
      module PrepareEnvironmentVariables
        private def prepare_environment_variables : Hash(String, String)
          process_env = ENV.to_h
        
          if terminal_name = @name
            process_env["TERM"] = terminal_name
          end
        
          if custom_env = @env
            process_env.merge!(custom_env)
          end
        
          process_env
        end
      end
    
      module SpawnChild
        private def spawn_child(slave_fd : Int32, args : Array(String)?) : NoReturn
          PTY::C.login_tty(slave_fd)
        
          # Propagate configurations into system environment space
          prepare_environment_variables.each do |key, value|
            ENV[key] = value
          end
        
          if directory = @cwd
            Dir.cd(directory) rescue nil
          end
        
          command_vector = args && !args.empty? ? args : [@shell]
          command = command_vector[0]
        
          Process.exec(
            command: command,
            args: command_vector.size > 1 ? command_vector[1..-1] : nil
          )
        
          PTY::C._exit(1)
        end
      end
    
      module StartSessionEngine
        private def start_session_engine(args : Array(String)?, stream_callback : (String ->)?)
          master_fd, slave_fd = allocate_pty
        
          # Apply initial hardware window bounds directly inside descriptor registers
          update_kernel_terminal_dimensions_by_fd(master_fd)
        
          pid = PTY::C.fork
          if pid < 0
            raise "Error: OS process fork failed."
          elsif pid == 0
            # INSIDE THE CHILD PROCESS SANDBOX
            spawn_child(slave_fd, args)
          else
            # INSIDE THE PARENT PROCESS PROXY
            @process = Process.new(Crystal::System::Process.new(pid))
            monitor_parent_stream(master_fd, slave_fd, stream_callback)
          end
        end
        
        private def allocate_pty : Tuple(Int32, Int32)
          if PTY::C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
            raise "Error: OS failed to allocate high-precision PTY descriptors."
          end
          {master_fd, slave_fd}
        end
      end
    
      module UpdateKernelTerminalDimensions
        private def update_kernel_terminal_dimensions
          if io = @master_io
            update_kernel_terminal_dimensions_by_fd(io.fd)
          end
        end
        
        private def update_kernel_terminal_dimensions_by_fd(fd : Int32)
          size = PTY::C::WinSize.new(ws_row: @rows.to_u16, ws_col: @columns.to_u16)
          tiocswinsz = 0x5414_u64 
          PTY::C.ioctl(fd, tiocswinsz, pointerof(size))
        end
      end
    
      # Starts the session. Overloaded to make streaming blocks completely optional.
      def start(args : Array(String)? = nil, &block : String ->)
        start_session_engine(args, block)
      end
      
      def start(args : Array(String)? = nil)
        start_session_engine(args, nil)
      end
      
      include StartSessionEngine
      
      include SpawnChild
      include MonitorParentStream
      include UpdateKernelTerminalDimensions
      include PrepareEnvironmentVariables
    end
  
    module Terminate
      # Cleans up resources cleanly and forces blocking loops to break immediately
      def terminate
        if process = @process
          Process.signal(Signal::KILL, process.pid) rescue nil
          process.wait rescue nil
          @process = nil
        end
      
        cleanup_streams
      end
      
      # Close the PTY handles to completely unblock the asynchronous read fiber loop
      private def cleanup_streams
        @master_io.try(&.close)
        @master_io = nil
        @process = nil
      end
      
      def alive? : Bool
        if process = @process
          !process.exists? || process.terminated? ? false : true
        else
          false
        end
      end
    end
  
    module Wait
      # Blocks the main execution thread cleanly until the process finishes running
      def wait : Int32
        if process = @process
          # Wait for the OS status to toggle natively
          status = process.wait
          cleanup_streams
      
          # Block efficiently until the reader loop finishes flushing remaining buffers
          @mutex.synchronize do
            while @reader_active
              @cond.wait(@mutex)
            end
      
            # Propagate asynchronous callback errors safely if caught
            if ex = @exception
              @exception = nil
              raise ex
            end
          end
      
          status.exit_code
        else
          raise "Session context missing: process has not been started yet."
        end
      end
    end
  
    module WaitFor
      class TimeoutError < Exception
      end
      
      # Blocks efficiently without wasting CPU loops until the target string arrives
      def wait_for(target : String, timeout : Time::Span = 2.seconds)
        start_time = Time.instant 
      
        @mutex.synchronize do
          # Loop safely manages spurious wakeups and tracks time limits dynamically
          while !@output.includes?(target)
            remaining = timeout - start_time.elapsed
            if remaining <= Time::Span::ZERO
              raise TimeoutError.new("Timed out waiting for '#{target}'")
            end
      
            # Blocks cleanly; instantly releases the lock so the reader fiber can write text,
            # then re-acquires the lock automatically the millisecond it gets signaled.
            @cond.wait(@mutex, remaining)
          end
        end
      end
    end
  
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
  end
end