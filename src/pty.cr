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
    fun kill(pid : Int32, sig : Int32) : Int32
    fun execve(path : UInt8*, argv : UInt8**, envp : UInt8**) : Int32
  end

  class ExecutionResult
    getter output : String
    getter status : Int32
    
    def initialize(@output : String, @status : Int32)
    end
  end

  class Queue(T)
    class ClosedError < Exception; end
    
    def initialize
      @deque = Deque(T).new
      @mutex = Sync::Mutex.new
      @cond = Sync::ConditionVariable.new(@mutex)
      @closed = false
    end
    
    def closed? : Bool
      @mutex.synchronize { @closed }
    end
    
    def close
      @mutex.synchronize do
        @closed = true
        @cond.broadcast # Wake up any waiting pops to let them see closure
      end
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
          raise ClosedError.new("Queue is closed") if @closed
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
  
  # Multiplexes standard stdout/stderr data strings with out-of-band life-changing events
  alias StreamMessage = String | Symbol

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
      private def add_queue(&block : PTY::Queue(PTY::StreamMessage) -> T) : Int32 forall T
        my_queue = PTY::Queue(PTY::StreamMessage).new
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
  
    module DebugLog
      # A specialized multi-line formatter for high-concurrency stream tracing
      private def debug_log(prefix : String, data : NamedTuple | Hash | String)
        # Prefix every event with its method so concurrent traces are easy to scan.
        method, separator, event = prefix.partition(" :: ")
        indent = "  "
      
        body = case data
               when String
                 data.inspect
               else
                 data.map { |k, v| "\n#{indent}#{indent}#{k}: #{v.inspect}" }.join
               end
      
        method_label = separator.empty? ? "unknown" : method
        event_label = separator.empty? ? prefix : event
        STDERR.puts "\e[36m[PTY DEBUG]\e[0m \e[35m[#{method_label}]\e[0m \e[33m[#{event_label}]\e[0m#{body}\n"
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
        @ingest_queue = PTY::Queue(String | Symbol).new
        @subscribers = Set(PTY::Queue(String | Symbol)).new
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
        @ingest_queue = PTY::Queue(String | Symbol).new
        @subscribers = Set(PTY::Queue(String | Symbol)).new
        @subscribers_mutex = Sync::Mutex.new
      
        # Securely box the initial empty string state into a raw atomic pointer reference
        @output_ptr = Atomic(Pointer(Void)).new(Box(String).box(""))
        @reader_active = Atomic(Bool).new(false)
      end
    end
  
    module Questions
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
  
    module Resize
      # Resizes the ongoing active subshell terminal window on-the-fly
      def resize(rows : Int32, columns : Int32)
        @rows = rows
        @columns = columns
        update_kernel_terminal_dimensions
      end
    end
  
    module Run
      module CommandSandwichComplete
        # Checks if the full execution transcript sandwich has successfully concluded
        private def command_sandwich_complete?(buffer : String, start_sentinel : String, end_sentinel : String) : Bool
          # 1. Locate where the literal sentinels begin in the stream
          start_idx = buffer.rindex(start_sentinel)
          # FIX: Locate the LAST (most recent) occurrence of the end sentinel string
          end_idx = buffer.rindex(end_sentinel)
        
          debug_log("command_sandwich_complete? :: Sandwich Index Scan", {
            start_sentinel_index: start_idx,
            end_sentinel_index: end_idx,
            valid_chronological_order: (start_idx && end_idx ? end_idx > start_idx : false)
          })
        
          return false unless start_idx && end_idx && end_idx > start_idx
        
          # 2. Extract the sliding window immediately following the end sentinel
          suffix = buffer[end_idx + end_sentinel.bytesize..-1]
        
          debug_log("command_sandwich_complete? :: Trailer Sliced Suffix", {
            extracted_suffix: suffix,
            starts_with_double_underscore: suffix.starts_with?("__")
          })
          
          # 3. Validate the structure of the evaluated trailing exit code block
          evaluation_result = extract_status_suffix(suffix)
        
          debug_log("command_sandwich_complete? :: Completeness Evaluation", {
            is_command_completely_finished: evaluation_result
          })
        
          evaluation_result
        end
        
        # Validates the "__STATUS__" wrapping envelope format without using regex
        private def extract_status_suffix(suffix : String) : Bool
          return false unless suffix.starts_with?("__")
          
          # Find the closing underscore delimiter, skipping the first two opening characters
          if closing_underscore_idx = suffix.index("__", 2)
            status_digits = suffix[2...closing_underscore_idx]
        
            debug_log("extract_status_suffix :: Exit Token Isolated", {
              isolated_digits: status_digits,
              is_strictly_numeric: valid_status_digits?(status_digits)
            })
        
            return valid_status_digits?(status_digits)
          end
        
          false
        end
        
        # Ensures the token consists strictly of evaluated digits, ignoring the literal "__$?__" echo
        private def valid_status_digits?(digits : String) : Bool
          # FIX: Chain `.chars` or `.each_char` before invoking `.all?`
          !digits.empty? && digits.chars.all?(&.ascii_number?)
        end
      end
    
      module DispatchSandwichCommands
        # Helper C: Transmits the text sandwich straight down the interactive line
        private def dispatch_sandwich_commands(command_string : String, start_sentinel : String, end_sentinel : String)
          # Run in a subshell so an "exit" command doesn't kill the persistent shell.
          wrapped_payload = "echo #{start_sentinel}; ( \n#{command_string}\n); echo #{end_sentinel}__$?__\n"
          write(wrapped_payload)
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
        module ExtractStatusCode
          # Extracts the evaluated integer return status from the tail of the transcript
          private def extract_status_code(transcript : String, end_sentinel : String) : Int32
            if end_idx = transcript.rindex(end_sentinel)
              suffix = transcript[end_idx + end_sentinel.bytesize..-1]
              if suffix.starts_with?("__") && (closing_idx = suffix.index("__", 2))
                status_digits = suffix[2...closing_idx]
                
                debug_log("extract_status_code :: Status Digits Extracted", {
                  status_digits: status_digits,
                  is_numeric: status_digits.chars.all?(&.ascii_number?)
                })
          
                if !status_digits.empty? && status_digits.chars.all?(&.ascii_number?)
                  return status_digits.to_i
                end
              end
            end
          
            raise "Could not extract command exit status from PTY transcript (sentinel #{end_sentinel})"
          end
        end
      
        module IsolateSandboxedPayload
          # Slices out only the text explicitly contained between the boundary walls
          private def isolate_sandboxed_payload(transcript : String, start_sentinel : String, end_sentinel : String) : String?
            start_pos = transcript.rindex(start_sentinel)
            end_pos = transcript.rindex(end_sentinel)
            
            debug_log("isolate_sandboxed_payload :: Boundary Slice Mapping", {
              start_pos: start_pos,
              end_pos: end_pos
            })
          
            if start_pos && end_pos && end_pos > start_pos
              return transcript[start_pos + start_sentinel.bytesize...end_pos]
            end
            nil
          end
        end
      
        module StripTerminalNoise
          # Strips control characters, shell prompts, and trailing carrier returns
          private def strip_terminal_noise(text : String) : String
            # Strip TTY spacing variables, shell markers ($), and root symbols (#)
            text.strip("\r\n$ #%")
          end
        end
      
        private def harvest_execution_block(
          snapshot_index : Int32,
          command_string : String,
          start_sentinel : String,
          end_sentinel : String,
          captured_text : String
        ) : PTY::ExecutionResult
          # 1. Audit the entry metrics and the raw incoming text data payload size
          transcript = output[snapshot_index..-1]
          
          debug_log("harvest_execution_block :: Invoked", {
            snapshot_index: snapshot_index,
            transcript_bytesize: transcript.bytesize,
            captured_text_bytesize: captured_text.bytesize
          })
        
          # 2. Extract exit state code using our reverse-index scanner
          exit_status = extract_status_code(transcript, end_sentinel)
        
          # 3. Clean the transcript block out of the sentinel sandboxed buffer
          clean_output = ""
          if raw_payload = isolate_sandboxed_payload(transcript, start_sentinel, end_sentinel)
            clean_output = strip_terminal_noise(raw_payload)
          end
        
          # 4. Fallback safeguard check if line formatting caused anomalies
          if clean_output.empty? && !captured_text.empty?
            debug_log("harvest_execution_block :: Captured Text Fallback", "")
            clean_output = strip_terminal_noise(captured_text)
          end
        
          # 5. Final output check confirming what the assertion block will receive
          debug_log("harvest_execution_block :: Completed Evaluation", {
            final_cleaned_output: clean_output,
            final_exit_status: exit_status
          })
        
          PTY::ExecutionResult.new(output: clean_output, status: exit_status)
        end
        
        include ExtractStatusCode
        include IsolateSandboxedPayload
        include StripTerminalNoise
      end
    
      # Streams execution chunks interactively in real time down an open session pipeline
      def run(command_string : String, &stream_callback : String ->) : PTY::ExecutionResult
        start_sentinel, end_sentinel = generate_sentinels
        captured_text = ""
      
        initial_snapshot_size = add_queue do |run_queue|
          dispatch_sandwich_commands(command_string, start_sentinel, end_sentinel)
      
          loop do
            message = run_queue.pop
            case message
            in String
              debug_log("run :: String Message", {
                message_chunk: message,
                total_accumulated_bytes: captured_text.bytesize
              })
      
              captured_text += message
              stream_callback.call(message)
      
              # FIX: Validate the end_sentinel is followed by an evaluated integer digit layout (__\d+__)
              # instead of a raw literal shell macro variable (__$?__), ensuring we never stop inside the input echo phase!
              if command_sandwich_complete?(captured_text, start_sentinel, end_sentinel)
                break
              end
            in Symbol
              debug_log("run :: Control Message", {
                event_token: message
              })
      
              case message
              when :session_closed
                break # Main process died, exit instantly
              when :stream_idle
                # The OS buffer is temporarily empty. Check if we already have the payload
                # Input echo can contain both sentinels before the command has finished.
                # Only stop when the end marker has an evaluated numeric exit status.
                if command_sandwich_complete?(captured_text, start_sentinel, end_sentinel)
                  break
                end
              when :subscriber_detached, :command_timeout
                break # Escape the blocking pop loop to prevent a permanent freeze
              end
            end
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
      include CommandSandwichComplete
      include HarvestExecutionBlock
    end
  
    module Start
      module MonitorParentStream
        module ProcessNextChunk
          private def process_next_chunk(chunk : String)
            # 1. Update the inherently thread-safe atomic pointer log
            update_history_snapshot(chunk)
          
            # Broadcast a copy of the chunk to every active listener queue safely
            @subscribers_mutex.synchronize do
              # Replace raw distribution inspection with:
              debug_log("process_next_chunk :: Distribution Fan-Out", {
                active_subscribers: @subscribers.size,
                fanning_chunk: chunk
              })
          
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
      
        module SpawnDistributionLoop
          private def spawn_distribution_loop
            spawn do
              begin
                loop do
                  message = @ingest_queue.pop
                  case message
                  in String
                    process_next_chunk(message)
                  in Symbol
                    if message == :stream_idle
                      # FAN-OUT EMIT: Broadcast the idle signal to all user listeners 
                      # so they know they can safely inspect their rolling caches.
                      @subscribers_mutex.synchronize do
                        @subscribers.each &.push(:stream_idle)
                      end
                    end
                  end
                end
              rescue ex : PTY::Queue::ClosedError
                # CRITICAL: Only broadcast :session_closed when the ingestion fiber 
                # explicitly closes the queue upon actual shell process termination!
                @subscribers_mutex.synchronize do
                  @subscribers.each &.push(:session_closed)
                end
              ensure
                @subscribers_mutex.synchronize do
                  @subscribers.clear
                end
              end
            end
          end
        end
      
        module SpawnIngestionLoop
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
                  chunk = String.new(io_buffer[0, bytes_read])
          
                  debug_log("spawn_ingestion_loop :: Received Data", {
                    bytes_read: bytes_read,
                    raw_payload: chunk
                  })
          
                  @ingest_queue.push(chunk)
                rescue ex : IO::Error
                  # Handle non-blocking retry signs gracefully
                  if ex.os_error == Errno::EAGAIN || ex.os_error == Errno::EWOULDBLOCK
                    # EMIT: Push a special in-band token to @ingest_queue signifying 
                    # that the OS kernel buffer is temporarily empty (idle).
                    @ingest_queue.push(:stream_idle)
                    Fiber.yield
                    sleep(1.millisecond)
                    next
                  else
                    break
                  end
                end
              end
              @reader_active.set(false)
              @ingest_queue.close # ◄─ Signal completion to the consumer layer
            end
          end
        end
      
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
        
        include SpawnIngestionLoop
        include SpawnDistributionLoop
        include ProcessNextChunk
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
        # Child-side work must avoid Crystal allocation/runtime code after fork.
        # All strings and pointer vectors are prepared in the parent before fork.
        private def execute_child_sandbox(
          master_fd : Int32,
          slave_fd : Int32,
          executable_path : Pointer(UInt8),
          target_cwd : Pointer(UInt8),
          argv : Pointer(Pointer(UInt8)),
          envp : Pointer(Pointer(UInt8))
        ) : NoReturn
          PTY::C.close(master_fd)
        
          # login_tty performs the native controlling-terminal/stdin/stdout/stderr setup.
          PTY::C._exit(127) unless PTY::C.login_tty(slave_fd) == 0
        
          # chdir is async-signal-safe; the pointer was staged before the fork.
          if target_cwd != Pointer(UInt8).null
            LibC.chdir(target_cwd)
          end
        
          # Do not call Process.exec here: it allocates/builds envp in Crystal after fork.
          PTY::C.execve(executable_path, argv, envp)
        
          # execve returns only on failure. Never unwind through Crystal in this child.
          PTY::C._exit(127)
        end
      end
    
      module InitializeParentProxy
        # Helper C: Hooks up tracking wrappers and boots background readers
        private def initialize_parent_proxy(pid : Int32, slave_fd : Int32, master_fd : Int32)
          PTY::C.close(slave_fd) rescue nil
          @process = Process.new(Crystal::System::Process.new(pid))
          @started.set(true)
        
          if child_pid = @process.try(&.pid)
            debug_log("initialize_parent_proxy :: Fork Handshake Successful", {
              allocated_child_pid: child_pid,
              master_fd: @master_io.try(&.fd)
            })
          else
            debug_log("initialize_parent_proxy :: Fork Allocation Error", "")
          end
        
          monitor_parent_stream(master_fd)
        
          debug_log("initialize_parent_proxy :: Background Workers Spawned", {
            reader_active_flag: @reader_active.get,
            ingest_queue_object_id: @ingest_queue.object_id
          })
        end
        
        include MonitorParentStream
      end
    
      module StagePreFlightPrimitives
        # Helper A: Packs arguments and environment completely before crossing the fork boundary
        private def stage_pre_flight_primitives : Tuple(Array(String), String, String, String?)
          process_env = prepare_environment_variables
          env_payload = process_env.map { |k, v| "#{k}=#{v}" }
        
          target_shell = @shell
          search_path = process_env["PATH"]? || "/usr/bin:/bin"
          target_executable = Process.find_executable(target_shell, search_path, @cwd || Dir.current) ||
            raise "PTY shell executable not found: #{target_shell}"
        
          {env_payload, target_shell, target_executable, @cwd}
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
        debug_log("start :: Boot Sequence Triggered", {
          target_shell: @shell,
          dimensions: "#{@rows} rows x #{@columns} columns",
          working_dir: @cwd,
          custom_env: @env
        })
      
        # Guard against booting an already running process.
        if @started.swap(true)
          debug_log("start :: Already Running", "")
          return self
        end
      
        # Pre-flight resolves PATH and builds every argument/environment string before
        # any fork. If the executable is invalid, no PTY descriptors have been allocated.
        begin
          env_payload, target_shell, target_executable, target_cwd = stage_pre_flight_primitives
        rescue ex
          @started.set(false)
          raise ex
        end
      
        argv = [target_shell.to_unsafe, Pointer(UInt8).null]
        envp = [] of Pointer(UInt8)
        env_payload.each { |entry| envp << entry.to_unsafe }
        envp << Pointer(UInt8).null

      
        # Keep all memory referenced by argv/envp rooted across any parent-side GC
        # that can run before fork; the child uses the inherited bytes directly.
        @child_launch_buffers = {env_payload, target_executable, argv, envp}
      
        # Evaluate all managed-string / Array accessors before fork. The child receives
        # only raw pointers to memory that already exists in its forked address space.
        executable_path_ptr = target_executable.to_unsafe
        target_cwd_ptr = target_cwd ? target_cwd.to_unsafe : Pointer(UInt8).null
        argv_ptr = argv.to_unsafe
        envp_ptr = envp.to_unsafe
      
        # Allocate descriptors only once pre-flight has succeeded.
        master_fd, slave_fd = allocate_pty
        update_kernel_terminal_dimensions_by_fd(master_fd)
      
        # Process Split Boundary
        pid = PTY::C.fork
        if pid < 0
          raise "Error: OS process fork failed."
        elsif pid == 0
          # INSIDE CHILD: pass only native pointers and file descriptors.
          execute_child_sandbox(master_fd, slave_fd, executable_path_ptr, target_cwd_ptr, argv_ptr, envp_ptr)
        else
          # INSIDE PARENT
          initialize_parent_proxy(pid, slave_fd, master_fd)
          debug_log("start :: Initial Shell Settlement Sync Guard", {
            waiting_for_token: "$ ",
            current_history_size: output.bytesize
          })
          wait_for("$ ") rescue nil
          @child_launch_buffers = nil
        end
      
        debug_log("start :: Boot Sequence Complete", {
          final_history_snapshot: output
        })
      
        self
      end
      
      include AllocatePTY
      include UpdateKernelTerminalDimensions
      include StagePreFlightPrimitives
      include ExecuteChildSandbox
      include InitializeParentProxy
    end
  
    module Terminate
      def terminate : Nil
        @reader_active.set(false)
      
        proc = @process
        process_group_id = proc.try(&.pid)
      
        # The PTY child starts a new session with its PID as its process-group ID.
        # Signal the whole group before closing the master descriptor, so cleanup
        # does not depend on the shell remaining alive.
        if pgid = process_group_id
          PTY::C.kill(-pgid, Signal::TERM.value)
        end
      
        # Close the master descriptor to unblock the reader loop.
        if io = @master_io
          begin
            io.close unless io.closed?
          rescue
          ensure
            @master_io = nil
          end
        end
      
        # Do not use proc.terminated? as the group-liveness check: the shell can
        # exit while a descendant in the same process group continues running.
        if pgid = process_group_id
          term_started_at = Time.instant
          while PTY::C.kill(-pgid, 0) == 0 && term_started_at.elapsed < 100.milliseconds
            sleep(5.milliseconds)
          end
      
          # Escalate against the group even when its original leader has exited.
          if PTY::C.kill(-pgid, 0) == 0
            PTY::C.kill(-pgid, Signal::KILL.value)
          end
        end
      
        Fiber.yield
      
        if proc
          proc.wait rescue nil
        end
      
        @process = nil
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
          debug_log("wait_for :: Engine Initialized", {
            tracking_target: target,
            timeout_threshold: timeout,
            queue_object_id: queue.object_id
          })
      
          loop do
            # 1. Enforce strict timeout thresholds
            if start_time.elapsed > timeout
              raise TimeoutError.new("Timed out waiting for '#{target}'")
            end
      
            debug_log("wait_for :: Iteration Guard Pass", {
              elapsed_seconds: start_time.elapsed.to_f,
              reader_active_state: @reader_active.get,
              backlogged_queue_elements: queue.size
            })
      
            # 2. Check for unexpected upstream pipe closures
            if !@reader_active.get && queue.size == 0
              break
            end
      
            # 3. Block-pop the next available text chunk out of the concurrent queue
            # This cleanly suspends the current fiber without locking execution threads
            message = queue.pop
            case message
            in String
              local_buffer += message
      
              debug_log("wait_for :: Received Data", {
                arrived_chunk: message,
                updated_local_buffer: local_buffer,
                match_detected: local_buffer.includes?(target)
              })
              # 4. Perform the boundary scan against the rolling localized context window
              if local_buffer.includes?(target)
                break
              end
            in Symbol
              debug_log("wait_for :: Control Signal", {
                control_token: message,
                remaining_elements_to_drain: queue.size
              })
      
              case message
              when :session_closed && queue.size == 0
                break
              end
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
    @child_launch_buffers : Tuple(Array(String), String, Array(Pointer(UInt8)), Array(Pointer(UInt8)))? = nil
    
    @process : Process?
    @master_io : IO::FileDescriptor?
    @exception : Exception? = nil
    @reader_active : Atomic(Bool)
    @active_run_callback : (String -> Nil)? = nil
    
    @subscribers : Set(PTY::Queue(String | Symbol))
    @subscribers_mutex : Sync::Mutex
    
    include Initialize
    include Start
    include Run
    include AddQueue
    include WaitFor
    include Write
    include Resize
    include Terminate
    include DebugLog
    include Questions
  end
end