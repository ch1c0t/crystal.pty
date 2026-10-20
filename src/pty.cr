require "uuid"

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
    fun kill(pid : Int32, signal : Int32) : Int32
    fun close(fd : Int32) : Int32
    fun ioctl(fd : Int32, request : UInt64, argp : Void*) : Int32
    fun tcgetpgrp(fd : Int32) : Int32
    fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
  end

  module Run
    # Runs a one-shot shell command in a pseudo-terminal. The transcript combines stdout
    # and stderr because both are attached to the same terminal.
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      session = Session.new(rows: rows, columns: columns)
      Command.new(command, session).execute_inside_pty(&stream_callback)
    end
    
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      session = Session.new(rows: rows, columns: columns)
      Command.new(command, session).execute_inside_pty
    end
    
    # Direct argv execution remains available through PTY.run without expanding
    # PTY::Command beyond its shell-string API.
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      session = Session.new(command, rows: rows, columns: columns).start(&stream_callback)
      exit_code = session.wait
      {session.output, exit_code}
    end
    
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      run(command, rows: rows, columns: columns) { |_chunk| }
    end
  end

  extend Run

  class Command
    module Initialize
      # Compatibility constructor used by tmux.run. The index and run_id remain part
      # of the public API; each execution delegates to an interactive Session.
      def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
        @session = Session.new
      end
      
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
    module Control
      def start(&stream_callback : String -> Nil) : self
        start_with_callback(stream_callback)
      end
      
      def start : self
        start_with_callback(->(chunk : String) { nil })
      end
      
      # Runs a command with the configured shell using the same PTY lifecycle.
      def execute(raw_string : String, stream_callback : String -> Nil) : self
        raise "PTY session has already been started" if @started
        @raw_string = raw_string
        @command = raw_string
        start(&stream_callback)
      end
      
      private def start_with_callback(callback : Proc(String, Nil)) : self
        raise "PTY session has already been started" if @started
      
        master_fd, slave_fd = allocate_pty(@rows, @columns)
        child_pid = C.fork
        if child_pid < 0
          C.close(master_fd)
          C.close(slave_fd)
          raise "fork failed while starting PTY session"
        elsif child_pid == 0
          spawn_child(master_fd, slave_fd)
        end
      
        C.close(slave_fd)
        @pid = child_pid
        @master_fd = master_fd
        @master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
        @reader_done = Channel(Exception?).new(1)
        @started = true
        spawn { read_output(callback) }
        wait_until_ready
        self
      end
      
      private def wait_until_ready : Nil
        deadline = Time.instant + 2.seconds
        until File.exists?(@ready_path) || File.exists?(@status_path)
          if Time.instant >= deadline
            terminate_child_group(@pid.not_nil!)
            wait_for_reader
            cleanup_session
            raise "PTY child did not become ready"
          end
          sleep(10.milliseconds)
        end
      
        File.delete(@ready_path) if File.exists?(@ready_path)
      ensure
        File.delete("#{@ready_path}.tmp") if File.exists?("#{@ready_path}.tmp")
      end
    end
  
    module Helpers
      module AllocatePTY
        private def allocate_pty(rows : Int32?, columns : Int32?) : Tuple(Int32, Int32)
          master_fd = 0
          slave_fd = 0
          result = if rows && columns
                     window_size = C::WinSize.new
                     window_size.ws_row = rows.to_u16
                     window_size.ws_col = columns.to_u16
                     window_size.ws_xpixel = 0_u16
                     window_size.ws_ypixel = 0_u16
                     C.openpty(pointerof(master_fd), pointerof(slave_fd), nil, nil, pointerof(window_size).as(Void*))
                   else
                     C.openpty(pointerof(master_fd), pointerof(slave_fd), nil, nil, nil)
                   end
        
          raise "Error: OS failed to allocate PTY descriptors." if result == -1
          {master_fd, slave_fd}
        end
      end
    
      module ReadOutput
        private def read_output(callback : Proc(String, Nil)) : Nil
          error : Exception? = nil
          io_buffer = Bytes.new(4096)
        
          begin
            loop do
              bytes_read = begin
                @master_io.not_nil!.read(io_buffer)
              rescue ex : IO::Error
                break
              end
              break if bytes_read <= 0
        
              chunk = String.new(io_buffer[0, bytes_read])
              @output_buffer.write(io_buffer[0, bytes_read])
              begin
                callback.call(chunk)
              rescue ex
                error = ex
                terminate_child_group(@pid.not_nil!)
                break
              end
            end
          rescue ex
            error = ex
            terminate_child_group(@pid.not_nil!)
          ensure
            @stream_error = error
            @reader_done.not_nil!.send(error)
          end
        end
      end
    
      module SpawnChild
        private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
          C.close(master_fd)
          C._exit(127) if C.login_tty(slave_fd) == -1
        
          begin
            ENV["TERM"] = @name
            if env = @env
              env.each { |key, value| ENV[key] = value }
            end
            Dir.cd(@cwd.not_nil!) if @cwd
            File.write(@ready_path, "ready\\n")
        
            if argv = @argv
              Process.exec(argv.first, argv[1..])
            elsif command = @command
              Process.exec(@shell, ["-c", command])
            else
              Process.exec(@shell, ["-i"])
            end
          rescue
            C._exit(127)
          end
          C._exit(127)
        end
      end
    
      module WaitForChild
        private def terminate_child_group(pid : Int32) : Nil
          groups = [pid] of Int32
          if fd = @master_fd
            foreground_group = C.tcgetpgrp(fd)
            groups << foreground_group if foreground_group > 0 && foreground_group != pid
          end
        
          groups.each { |group| C.kill(-group, 1) }
          sleep(50.milliseconds)
          groups.each { |group| C.kill(-group, 9) }
          C.kill(pid, 9)
        end
      end
    
      include AllocatePTY
      include SpawnChild
      include ReadOutput
      include WaitForChild
    end
  
    module Initialize
      def initialize(
        *,
        name : String = "xterm-256color",
        rows : Int32? = nil,
        columns : Int32? = nil,
        cwd : String? = nil,
        env : Hash(String, String)? = nil
      )
        initialize(ENV["SHELL"]? || "/bin/sh", name: name, rows: rows, columns: columns, cwd: cwd, env: env)
      end
      
      def initialize(
        shell : String,
        *,
        name : String = "xterm-256color",
        rows : Int32? = nil,
        columns : Int32? = nil,
        cwd : String? = nil,
        env : Hash(String, String)? = nil
      )
        raise ArgumentError.new("PTY shell must not be empty") if shell.empty?
        @shell = shell
        @name = name
        @cwd = cwd
        @env = env
        @raw_string = ""
        @argv = nil
        @command = nil
        @interactive_shell = true
        @rows = rows
        @columns = columns
        @status_path = "/tmp/#{UUID.random}.pty_status"
        @ready_path = "#{@status_path}.ready"
        @pid = nil
        @exit_code = nil
        @master_fd = nil
        @master_io = nil
        @reader_done = nil
        @output_buffer = IO::Memory.new
        @started = false
        @completed = false
        @terminated = false
        @reader_finished = false
        @stream_error = nil
        validate_dimensions(rows, columns)
      end
      
      # Direct argv execution remains supported by PTY.run(Array(String)).
      def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
        raise ArgumentError.new("PTY command must not be empty") if argv.empty?
        raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?
      
        @argv = argv.dup
        @shell = ENV["SHELL"]? || "/bin/sh"
        @name = "xterm-256color"
        @cwd = nil
        @env = nil
        @command = nil
        @interactive_shell = false
        @raw_string = argv.join(" ")
        @rows = rows
        @columns = columns
        @status_path = "/tmp/#{UUID.random}.pty_status"
        @ready_path = "#{@status_path}.ready"
        @pid = nil
        @exit_code = nil
        @master_fd = nil
        @master_io = nil
        @reader_done = nil
        @output_buffer = IO::Memory.new
        @started = false
        @completed = false
        @terminated = false
        @reader_finished = false
        @stream_error = nil
        validate_dimensions(rows, columns)
      end
      
      private def validate_dimensions(rows : Int32?, columns : Int32?) : Nil
        if rows.nil? != columns.nil?
          raise ArgumentError.new("PTY rows and columns must be provided together")
        end
        if rows && (rows < 1 || rows > 65_535)
          raise ArgumentError.new("PTY rows must be between 1 and 65535")
        end
        if columns && (columns < 1 || columns > 65_535)
          raise ArgumentError.new("PTY columns must be between 1 and 65535")
        end
      end
    end
  
    module Input
      def write(data : String) : Nil
        raise "PTY session has not been started" unless @started
        raise "PTY session has completed" if @completed
      
        master_io = @master_io.not_nil!
        master_io.write(data.to_slice)
        master_io.flush
      end
      
      def resize(*, rows : Int32, columns : Int32) : Nil
        raise "PTY session has not been started" unless @started
        raise "PTY session has completed" if @completed
        validate_dimensions(rows, columns)
      
        size = C::WinSize.new
        size.ws_row = rows.to_u16
        size.ws_col = columns.to_u16
        size.ws_xpixel = 0_u16
        size.ws_ypixel = 0_u16
        result = C.ioctl(@master_fd.not_nil!, 0x5414_u64, pointerof(size).as(Void*))
        raise "ioctl(TIOCSWINSZ) failed" if result == -1
      
        @rows = rows
        @columns = columns
      end
      
      def alive? : Bool
        return false unless @started
        return false if @completed || File.exists?(@status_path)
      
        if child_pid = @pid
          C.kill(child_pid, 0) == 0
        else
          false
        end
      end
    end
  
    module Wait
      def wait : Int32
        raise "PTY session has not been started" unless @started
        return @exit_code.not_nil! if @completed
      
        code = wait_for_status
        wait_for_reader
        @exit_code = code
        @completed = true
        raise @stream_error.not_nil! if @stream_error
        code
      ensure
        cleanup_session if @completed
      end
      
      def terminate : Int32
        return @exit_code.not_nil! if @completed
        raise "PTY session has not been started" unless @started
      
        @terminated = true
        terminate_child_group(@pid.not_nil!)
        wait
      end
      
      def close : Int32
        terminate
      end
      
      private def wait_for_status : Int32
        pid = @pid.not_nil!
        loop do
          status = 0
          result = C.waitpid(pid, pointerof(status), 1)
          return decode_wait_status(status) if result == pid
          return 143 if @terminated && result < 0
          return 127 if result < 0
      
          unless @reader_finished
            select
            when error = @reader_done.not_nil!.receive
              @reader_finished = true
              @stream_error ||= error
              terminate_child_group(pid) if @stream_error
            when timeout(10.milliseconds)
            end
          else
            sleep(10.milliseconds)
          end
        end
      end
      
      private def decode_wait_status(status : Int32) : Int32
        signal = status & 0x7f
        signal == 0 ? (status >> 8) & 0xff : 128 + signal
      end
      
      private def wait_for_reader : Nil
        return if @reader_finished
      
        select
        when error = @reader_done.not_nil!.receive
          @reader_finished = true
          @stream_error ||= error
        when timeout(2.seconds)
          terminate_child_group(@pid.not_nil!)
          error = @reader_done.not_nil!.receive
          @reader_finished = true
          @stream_error ||= error
        end
      end
      
      private def cleanup_session : Nil
        @master_io.try &.close
        @master_io = nil
        @master_fd = nil
        File.delete(@status_path) if File.exists?(@status_path)
        File.delete("#{@status_path}.tmp") if File.exists?("#{@status_path}.tmp")
        File.delete(@ready_path) if File.exists?(@ready_path)
        File.delete("#{@ready_path}.tmp") if File.exists?("#{@ready_path}.tmp")
      end
    end
  
    getter raw_string : String
    getter rows : Int32?
    getter columns : Int32?
    getter status_path : String
    getter pid : Int32?
    getter exit_code : Int32?
    
    @argv : Array(String)?
    @shell : String
    @name : String
    @cwd : String?
    @env : Hash(String, String)?
    @command : String?
    @interactive_shell : Bool
    @master_fd : Int32?
    @master_io : IO::FileDescriptor?
    @reader_done : Channel(Exception?)?
    @output_buffer : IO::Memory
    @started : Bool
    @completed : Bool
    @terminated : Bool
    @reader_finished : Bool
    @stream_error : Exception?
    
    include Initialize
    include Helpers
    include Control
    include Input
    include Wait
    
    def output : String
      @output_buffer.to_s
    end
  end
end