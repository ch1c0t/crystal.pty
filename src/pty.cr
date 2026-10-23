require "sync/mutex"
require "sync/condition_variable"

module PTY
  class Box(T)
    # Core helper class to bridge heap allocations across raw pointers
    def initialize(@value : T)
    end
    
    def value : T
      @value
    end
    
    def self.box(value : T) : Pointer(Void)
      new(value).as(Pointer(Void))
    end
    
    def self.unbox(pointer : Pointer(Void)) : T
      pointer.as(Box(T)).value
    end
  end

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

  class ExecutionResult
    getter output : String
    getter status : Int32
    
    def initialize(@output : String, @status : Int32)
    end
  end

  class Queue(T)
    def initialize
      @deque = Deque(T).new
      @mutex = Sync::Mutex.new
      @cond = Sync::ConditionVariable.new(@mutex)
    end
    
    # Ruby's Queue#push (never blocks, wakes up waiting pops)
    def push(item : T)
      @mutex.synchronize do
        @deque.push(item)
        @cond.signal # Wake up one fiber waiting in #pop
      end
    end
    
    # Ruby's Queue#pop (blocks the fiber until an item is pushed)
    def pop : T
      @mutex.synchronize do
        while @deque.empty?
          # https://crystal-lang.org/api/master/Sync/ConditionVariable.html
          @cond.wait # Temporarily releases mutex and suspends fiber
        end
        @deque.shift # FIFO extraction
      end
    end
    
    def size : Int32
      @mutex.synchronize { @deque.size }
    end
  end

  module Run
    # Runs a one-shot shell command in a pseudo-terminal. The transcript combines stdout
    # and stderr because both are attached to the same terminal.
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      # Resolve nil values safely to match the strict Int32 constructor requirements
      session = Session.new(rows: rows || 24, columns: columns || 80)
      Command.new(command, session.start).execute_inside_pty(&stream_callback)
    end
    
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      session = Session.new(rows: rows || 24, columns: columns || 80)
      Command.new(command, session.start).execute_inside_pty
    end
  end

  extend Run

  class Command
    module Initialize
      @session : PTY::Session
      @owns_session : Bool
      
      # Constructor A: Command creates its own session instance
      def initialize(@raw_string : String)
        @session = Session.new
        @owns_session = true # Mark that this instance handles its own cleanup
      end
      
      # Constructor B: Command adopts a pre-existing session context shared by others
      def initialize(@raw_string : String, @session : PTY::Session)
        @owns_session = false # Do not kill this session; someone else is managing it
      end
    end
  
    getter raw_string : String
    getter session : Session
    
    include Initialize
    
    alias Output = String
    alias ExitCode = Int32
    
    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(Output, ExitCode)
      # Automatically start the session right at the execution threshold if it's not yet open
      if !@session.started?
        @session.start
      end
    
      # 1. Execute the string script natively over the interactive wire pipeline
      result = @session.run(@raw_string, &stream_callback)
    
      # 2. Only terminate the session if this specific command created it natively
      if @owns_session
        @session.terminate
      end
    
      {result.output, result.status}
    end
    
    def execute_inside_pty : Tuple(Output, ExitCode)
      execute_inside_pty { |_chunk| }
    end
  end

  class Session
    module AddQueue
      # Registers a private queue, yields it to the caller, and guarantees cleanup
      private def add_queue(&block : PTY::Queue(String) -> Nil) : Int32
        my_queue = PTY::Queue(String).new
        snapshot_size = 0
      
        @subscribers_mutex.synchronize do
          @subscribers.add(my_queue)
          snapshot_size = output.bytesize # <- Safely captured inside the exact same lock!
        end
      
        begin
          yield my_queue
        ensure
          @subscribers_mutex.synchronize { @subscribers.delete(my_queue) }
        end
      
        snapshot_size
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
        @started = Atomic(Bool).new(false)
        @ingest_queue = PTY::Queue(String).new
        @subscribers = Set(PTY::Queue(String)).new
        @subscribers_mutex = Sync::Mutex.new
      
        # Securely box the initial empty string state into a raw atomic pointer reference
        @output_ptr = Atomic(Pointer(Void)).new(Box(String).box(""))
        @reader_active = Atomic(Bool).new(false)
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
        @started = Atomic(Bool).new(false)
        @ingest_queue = PTY::Queue(String).new
        @subscribers = Set(PTY::Queue(String)).new
        @subscribers_mutex = Sync::Mutex.new
      
        # Securely box the initial empty string state into a raw atomic pointer reference
        @output_ptr = Atomic(Pointer(Void)).new(Box(String).box(""))
        @reader_active = Atomic(Bool).new(false)
      end
    end
  
    module Resize
      # Resizes the ongoing active subshell terminal window on-the-fly
      def resize(rows : Int32, columns : Int32)
        @rows = rows
        @columns = columns
        update_kernel_terminal_dimensions
      end
    end
  
    module Run
      module DispatchSandwichCommands
        # Helper C: Transmits the text sandwich straight down the interactive line
        private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
          write("echo #{start_sentinel}\n")
          write("#{command_string}\n") unless command_string.empty?
          write("echo #{end_sentinel}__$?__\n")
        end
      end
    
      module GenerateSentinels
        # Helper A: Generates the boundary walls
        private def generate_sentinels : Tuple(String, String)
          timestamp = Time.utc.to_unix_ms
          rand_id = Random.rand(100..999)
        
          start_sentinel = "START_MARK_#{timestamp}_#{rand_id}"
          end_sentinel   = "END_MARK_#{timestamp}_#{rand_id}"
          {start_sentinel, end_sentinel}
        end
      end
    
      module HarvestExecutionBlock
        module ExtractExitCode
          # Helper 1: Queries the exit status from the end sentinel or raw process table
          private def extract_exit_code(command_transcript : String, end_sentinel : String) : Int32
            if match = command_transcript.match(/#{end_sentinel}__(\d+)__/)
              return match[1].not_nil!.to_i
            end
          
            if !@reader_active && (proc = @process)
              return proc.wait.exit_code rescue 0
            end
          
            0
          end
        end
      
        module FallbackCleanText
          # Helper 3: Secondary cleanup filter block targeting raw real-time captured buffers
          private def fallback_clean_text(
            captured_text : String, 
            command_string : String, 
            start_sentinel : String, 
            end_sentinel : String
          ) : String
            captured_text
              .gsub(/#{Regex.escape(command_string)}\r?\n/, "")
              .gsub(/echo START_MARK_.+?\r?\n/, "")
              .gsub(/echo #{end_sentinel}__\$\?__\r?\n/, "")
              .sub(/^[\$\%\#]\s*/, "")
              .strip
          end
        end
      
        module FilterInfrastructureLines
          private def filter_infrastructure_lines(
            transcript : String, 
            command_string : String, 
            start_sentinel : String, 
            end_sentinel : String
          ) : String
            clean_lines = [] of String
            
            transcript.each_line do |line|
              trimmed_line = line.strip
          
              # 1. Skip core infrastructure sentinel rows cleanly using explicit words
              next if trimmed_line.includes?("START_MARK")
              next if trimmed_line.includes?("END_MARK")
              
              # 2. FIXED: Catch split trailing sentinel fragments (like "738_730__$?__") 
              # by checking if the row ends with the unique sentinel indicator sequence
              next if trimmed_line.ends_with?("__$?__")
              next if trimmed_line.includes?("__") && trimmed_line.ends_with?("__")
          
              # 3. Clean out direct input command echoes
              clean_line = line.gsub(/#{Regex.escape(command_string)}/, "").strip
              
              # 4. Strip leading prompt indicators cleanly without a complex regex matcher
              if clean_line.starts_with?('$') || clean_line.starts_with?('%') || clean_line.starts_with?('#')
                clean_line = clean_line[1..-1].strip
              end
              
              clean_lines << clean_line unless clean_line.empty?
            end
          
            clean_lines.join("\n").strip
          end
        end
      
        # Isolates the captured text and extracts the exit status safely
        private def harvest_execution_block(
          snapshot_index : Int32, 
          command_string : String, 
          start_sentinel : String, 
          end_sentinel : String, 
          captured_text : String
        ) : PTY::ExecutionResult
        
          command_transcript = output[snapshot_index..-1]
        
          # Step 1: Extract status
          exit_status = extract_exit_code(command_transcript, end_sentinel)
        
          # Step 2: Line-by-line infrastructure filtering
          clean_output = filter_infrastructure_lines(command_transcript, command_string, start_sentinel, end_sentinel)
        
          # Step 3: Fallback verification if the line buffer yielded an empty block
          if clean_output.empty? && !captured_text.empty?
            clean_output = fallback_clean_text(captured_text, command_string, start_sentinel, end_sentinel)
          end
        
          PTY::ExecutionResult.new(output: clean_output, status: exit_status)
        end
        
        include ExtractExitCode
        include FilterInfrastructureLines
        include FallbackCleanText
      end
    
      # Streams execution chunks interactively in real time down an open session pipeline
      def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
        start_sentinel, end_sentinel = generate_sentinels
        captured_text = ""
      
        initial_snapshot_size = add_queue do |run_queue|
          dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)
      
          loop do
            chunk = run_queue.pop
            captured_text += chunk
            stream_callback.call(chunk)
            break if captured_text.includes?(end_sentinel)
          end
        end
      
      
        # Extract clean results out of the sandboxed boundaries
        harvest_execution_block(
          initial_snapshot_size, 
          command_string, 
          start_sentinel, 
          end_sentinel, 
          captured_text
        )
      end
      
      # Overload matching block-less execution requests
      def run(command_string : String) : PTY::ExecutionResult
        run(command_string) { |_chunk| }
      end
      
      include GenerateSentinels
      include DispatchSandwichCommands
      include HarvestExecutionBlock
    end
  
    module Start
      module MonitorParentStream
        private def monitor_parent_stream(master_fd : Int32)
          setup_io_handles(master_fd)
          spawn_ingestion_loop
          spawn_distribution_loop
        end
        
        private def setup_io_handles(master_fd : Int32)
          master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
          IO::FileDescriptor.set_blocking(master_fd, false)
          @master_io = master_io
          @reader_active.set(true)
        end
        
        private def spawn_ingestion_loop
          spawn do
            io_buffer = Bytes.new(65536)
            master_io = @master_io.not_nil!
        
            loop do
              break if master_io.closed?
              begin
                bytes_read = master_io.read(io_buffer)
                break if bytes_read == 0
        
                # Move the data instantly into our thread-safe queue
                @ingest_queue.push(String.new(io_buffer[0, bytes_read]))
              rescue ex : IO::Error
                # Handle non-blocking retry signs gracefully
                next if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
                break
              end
            end
            @reader_active.set(false)
          end
        end
        
        private def spawn_distribution_loop
          spawn do
            loop do
              # Keep processing until ingestion stops and the queue is completely empty
              break if !@reader_active.get && @ingest_queue.size == 0
        
              chunk = @ingest_queue.pop
              process_next_chunk(chunk)
            end
          end
        end
        
        private def process_next_chunk(chunk : String)
          # 1. Update the inherently thread-safe atomic pointer log
          update_history_snapshot(chunk)
        
          # Broadcast a copy of the chunk to every active listener queue safely
          @subscribers_mutex.synchronize do
            @subscribers.each &.push(chunk)
          end
        end
        
        private def update_history_snapshot(chunk : String)
          loop do
            old_ptr = @output_ptr.get
            current_string = Box(String).unbox(old_ptr)
        
            # Combine into a new immutable string allocation
            new_string = current_string + chunk
            new_ptr = Box(String).box(new_string)
        
            # Perform the lockless atomic swap
            if @output_ptr.compare_and_set(old_ptr, new_ptr)
              break
            end
          end
        end
      end
    
      module AllocatePTY
        private def allocate_pty : Tuple(Int32, Int32)
          if PTY::C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
            raise "Error: OS failed to allocate high-precision PTY descriptors."
          end
          {master_fd, slave_fd}
        end
      end
    
      module ExecuteChildSandbox
        # Helper B: Light, GC-free execution boundary inside the cloned fork
        private def execute_child_sandbox(slave_fd : Int32, env_payload : Array(String), target_cwd : String?, target_shell : String) : NoReturn
          PTY::C.login_tty(slave_fd)
        
          # Direct POSIX LibC mutations skip high-level language object allocations
          # 1. Apply environment variables using raw string copies 
          # without touching Crystal's heavy ENV wrapper object
          env_payload.each do |env_string|
            # Split out the key/value parts safely using primitive byte manipulation
            if idx = env_string.index('=')
              k = env_string[0...idx]
              v = env_string[idx + 1..-1]
              # Call LibC directly to bypass Crystal heap allocations entirely
              LibC.setenv(k.to_unsafe, v.to_unsafe, 1)
            end
          end
        
          # 2. Safely change directory locally inside the child sandbox
          if target_cwd
            LibC.chdir(target_cwd.to_unsafe)
          end
        
          # Overwrite the child memory stack instantly
          Process.exec(target_shell)
          PTY::C._exit(1)
        end
      end
    
      module InitializeParentProxy
        # Helper C: Hooks up tracking wrappers and boots background readers
        private def initialize_parent_proxy(pid : Int32, slave_fd : Int32, master_fd : Int32)
          PTY::C.close(slave_fd) rescue nil
          @process = Process.new(Crystal::System::Process.new(pid))
          @started.set(true)
          monitor_parent_stream(master_fd)
        end
        
        include MonitorParentStream
      end
    
      module StagePreFlightPrimitives
        # Helper A: Packs our bags completely before crossing the border
        private def stage_pre_flight_primitives : Tuple(Array(String), String, String?)
          env_payload = prepare_environment_variables.map { |k, v| "#{k}=#{v}" }
          {env_payload, @shell, @cwd}
        end
        
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
    
      # STRICTLY starts a vanilla interactive shell session without inputs or blocks
      def start : self
        return self if started?
      
        # Phase 1: Allocate system virtual descriptors
        master_fd, slave_fd = allocate_pty
        update_kernel_terminal_dimensions_by_fd(master_fd)
      
        # Phase 2: Pre-Flight Staging (Run on the mainland parent heap)
        env_payload, target_shell, target_cwd = stage_pre_flight_primitives
      
        # Phase 3: The Process Split Boundary
        pid = PTY::C.fork
        if pid < 0
          raise "Error: OS process fork failed."
        elsif pid == 0
          # INSIDE CHILD
          execute_child_sandbox(slave_fd, env_payload, target_cwd, target_shell)
        else
          # INSIDE PARENT
          initialize_parent_proxy(pid, slave_fd, master_fd)
        end
        self
      end
      
      include AllocatePTY
      include UpdateKernelTerminalDimensions
      include StagePreFlightPrimitives
      include ExecuteChildSandbox
      include InitializeParentProxy
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
        @started.set(false)
      end
      
      def alive? : Bool
        if process = @process
          !process.exists? || process.terminated? ? false : true
        else
          false
        end
      end
      
      # Returns whether the pseudo-terminal descriptors have been booted
      def started? : Bool
        @started.get
      end
    end
  
    module WaitFor
      class TimeoutError < Exception
      end
      
      # Blocks cleanly using message passing; immune to split-buffer fragmentation
      def wait_for(target : String, timeout : Time::Span = 2.seconds) : String
        start_time = Time.instant
        local_buffer = ""
      
        add_queue do |queue|
          loop do
            # 1. Enforce strict timeout thresholds
            if start_time.elapsed > timeout
              raise TimeoutError.new("Timed out waiting for '#{target}'")
            end
      
            # 2. Check for unexpected upstream pipe closures
            if !@reader_active.get && queue.size == 0
              break
            end
      
            # 3. Block-pop the next available text chunk out of the concurrent queue
            # This cleanly suspends the current fiber without locking execution threads
            chunk = queue.pop
            local_buffer += chunk
      
            # 4. Perform the boundary scan against the rolling localized context window
            if local_buffer.includes?(target)
              break
            end
          end
        end
      
        local_buffer
      end
    end
  
    module Write
      # Feeds text commands natively to the child process's STDIN wire
      def write(command : String)
        if io = @master_io
          io.write(command.to_slice)
          io.flush
        else
          raise "PTY pipeline unavailable: call #start first."
        end
      end
    end
  
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
  end
end