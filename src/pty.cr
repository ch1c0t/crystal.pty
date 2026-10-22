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

  class ExecutionResult
    getter output : String
    getter status : Int32
    
    def initialize(@output : String, @status : Int32)
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
    module Execute
      # Backward compatibility adapter for one-shot block commands (Command class)
      def execute(command_string : String, stream_callback : (String -> Nil)?)
        if callback = stream_callback
          run(command_string) { |chunk| callback.call(chunk) }
        else
          run(command_string)
        end
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
        @started = Atomic(Bool).new(false)
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
        @started = Atomic(Bool).new(false)
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
        private def harvest_execution_block(
          snapshot_index : Int32, 
          command_string : String, 
          start_sentinel : String, 
          end_sentinel : String, 
          captured_text : String
        ) : PTY::ExecutionResult
        
          command_transcript = @output[snapshot_index..-1]
          exit_status = 0
        
          # 1. Harvest the exact numeric exit status code cleanly from the end token
          if match = command_transcript.match(/#{end_sentinel}__(\d+)__/)
            exit_status = match[1].to_i
          else
            if !@reader_active && (proc = @process)
              exit_status = proc.wait.exit_code rescue 0
            end
          end
        
          # 2. LINE-BY-LINE BLOCK HARVESTER (100% Immune to out-of-order buffering)
          # Split the transcript into component lines and filter out any infrastructure rows.
          clean_lines = [] of String
          
          command_transcript.each_line do |line|
            # Skip infrastructure echoes, sentinel keywords, and standalone trailing shell prompts
            next if line.includes?(start_sentinel)
            next if line.includes?(end_sentinel)
            next if line.includes?("echo START_MARK")
            next if line.includes?("echo END_MARK")
            next if line.strip == "$" || line.strip == "%"
            
            # Strip out direct input command echoes cleanly
            clean_line = line.gsub(/#{Regex.escape(command_string)}/, "").strip
            clean_lines << clean_line unless clean_line.empty?
          end
        
          clean_output = clean_lines.join("\n").strip
        
          # Fallback to the raw captured text if the line parser yields an empty block
          if clean_output.empty? && !captured_text.empty?
            clean_output = captured_text
              .gsub(/#{Regex.escape(command_string)}\r?\n/, "")
              .gsub(/echo START_MARK_.+?\r?\n/, "")
              .gsub(/echo END_MARK_.+?\r?\n/, "")
              .strip
          end
        
          PTY::ExecutionResult.new(output: clean_output, status: exit_status)
        end
      end
    
      module LiveFilter
        # Helper B: Binds the lossless real-time stream pipe hooks
        private def activate_live_filter(accumulator : String -> Nil)
          @mutex.synchronize do
            @active_run_callback = ->(chunk : String) { accumulator.call(chunk) }
          end
        end
        
        private def deactivate_live_filter
          @mutex.synchronize do
            @active_run_callback = nil
          end
        end
      end
    
      # Streams execution chunks interactively in real time down an open session pipeline
      def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
        initial_snapshot_size = @output.bytesize
        start_sentinel, end_sentinel = generate_sentinels
        captured_text = ""
      
        # Phase 1: Setup live real-time routing listener
        activate_live_filter(->(chunk : String) {
          captured_text += chunk
          stream_callback.call(chunk)
        })
      
        # Phase 2: Dispatch wrapped terminal commands and block until done
        dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)
        wait_for(end_sentinel)
        deactivate_live_filter
      
        # Phase 3: Extract clean results out of the sandboxed boundaries
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
      
      # -------------------------------------------------------------
      # The 4 Easy-To-Remember Private Helpers
      # -------------------------------------------------------------
      
      # Helper A: Generates the boundary walls
      include GenerateSentinels
      
      # Helper B: Binds the lossless real-time stream pipe hooks
      include LiveFilter
      
      # Helper C: Transmits the text sandwich straight down the interactive line
      include DispatchSandwichCommands
      
      # Helper D:
      include HarvestExecutionBlock
    end
  
    module Start
      module MonitorParentStream
        private def monitor_parent_stream(master_fd : Int32)
          master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
          IO::FileDescriptor.set_blocking(master_fd, false)
          @master_io = master_io
        
          @reader_active = true
        
          spawn do
            io_buffer = Bytes.new(65536)
            
            # FIX WORKAROUND FOR CRYSTAL BUG #15011:
            # Explicitly declare ALL loop-accessed variables here to anchor their scope
            # before entering the nested while/begin/rescue block structure.
            bytes_read = 0
            chunk = ""
            proc = @process
            active_cmd_hook = @active_run_callback
        
            while !master_io.closed?
              begin
                bytes_read = master_io.read(io_buffer)
                break if bytes_read == 0
        
                chunk = String.new(io_buffer[0, bytes_read])
                
                @mutex.synchronize do
                  @output += chunk
                  
                  # Fetch the callback pointer safely using our pre-declared variable frame
                  active_cmd_hook = @active_run_callback
                  if active_cmd_hook
                    begin
                      active_cmd_hook.call(chunk)
                    rescue ex : Exception
                      # FIX WORKAROUND FOR BUG #15011:
                      # Use a dedicated method call to force proper instance-level 
                      # assignment, breaking out of the shadowed compiler loop bug.
                      p "#{ex} in #monitor_parent_stream"
                      set_exception(ex)
        
                      master_io.close rescue nil
        
                      proc = @process
                      Process.signal(Signal::KILL, proc.pid) if proc rescue nil
                      @reader_active = false
                      @cond.broadcast
                      break
                    end
                  end
        
                  @cond.broadcast 
                end
              rescue ex : IO::Error
                if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
                  sleep(1.millisecond)
                  next
                else
                  break
                end
              end
            end
        
            @mutex.synchronize do
              @reader_active = false
              @cond.broadcast
            end
          end
        end
        
        private def set_exception(ex : Exception)
          p "#{ex} in #set_exception"
          @exception = ex
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
              @cond.wait
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
      
      # Blocks cleanly and ensures no background fiber broadcasts are ever missed
      def wait_for(target : String, timeout : Time::Span = 2.seconds)
        start_time = Time.instant 
      
        @mutex.synchronize do
          # 1. Loop continuously until the string manifests or time runs out
          while !@output.includes?(target)
            if start_time.elapsed > timeout
              raise TimeoutError.new("Timed out waiting for '#{target}'")
            end
      
            # Instantly raise the callback error if one was registered in the background
            p "in #wait_for, before exin"
            if ex = @exception
              p "#{ex} in #wait_for, in ex"
              @exception = nil
              raise ex
            end
      
            # FIXED CONCURRENCY CHECK: If the background reader fiber has completely 
            # shut down, the pipeline is closed. Break immediately to prevent hangs!
            unless @reader_active
              break
            end
      
            # 2. Release the mutex lock briefly to let the background reader fiber 
            # write text chunks, and sleep for a tiny slice to yield priority.
            @mutex.unlock
            begin
              sleep(5.milliseconds)
            ensure
              # 3. Automatically re-acquire the lock safely before checking the loop condition again
              @mutex.lock
            end
          end
          
          # =======================================================================
          # THE ABSOLUTE GATE CHECK (FIXES THE BYPASS RACE CONDITION)
          # =======================================================================
          # If the loop exited because the target was found, but the background fiber 
          # encountered a callback exception on that exact chunk step, we must 
          # prioritize raising the error over a clean return!
          if ex = @exception
            @exception = nil
            raise ex
          end
      
          # 4. Give the reader loop one final tiny slice to let closely trailing characters settle
          # Give the background loop extra dedicated microsecond slices to finish
          # draining high-velocity buffers completely before we return control!
          3.times do
            @mutex.unlock
            begin
              Fiber.yield
              sleep(1.millisecond)
            ensure
              @mutex.lock
            end
          end
        end
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
  end
end