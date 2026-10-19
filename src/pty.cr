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
  end

  module Run
    # Runs a one-shot command in a pseudo-terminal. The transcript combines stdout
    # and stderr because both are attached to the same terminal.
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
    end
    
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, &stream_callback : String -> Nil) : Tuple(String, Int32)
      Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
    end
    
    def run(command : String, *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      Command.new(command, rows: rows, columns: columns).execute_inside_pty
    end
    
    def run(command : Array(String), *, rows : Int32? = nil, columns : Int32? = nil) : Tuple(String, Int32)
      Command.new(command, rows: rows, columns: columns).execute_inside_pty
    end
  end

  extend Run

  class Command
    module Initialize
      # Compatibility constructor used by tmux.run. The index and run_id remain part
      # of the public API; each execution delegates to a Session using this status path.
      def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
        @argv = nil
        @rows = nil
        @columns = nil
        @status_path = "/tmp/#{UUID.random}.pty_status"
      end
      
      def initialize(@raw_string : String)
        @argv = nil
        @rows = nil
        @columns = nil
        @status_path = "/tmp/#{UUID.random}.pty_status"
      end
      
      def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil)
        @argv = nil
        @rows = rows
        @columns = columns
        @status_path = "/tmp/#{UUID.random}.pty_status"
        validate_window_size
      end
      
      def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
        raise ArgumentError.new("PTY command must not be empty") if argv.empty?
        raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?
      
        @argv = argv.dup
        @raw_string = argv.join(" ")
        @rows = rows
        @columns = columns
        @status_path = "/tmp/#{UUID.random}.pty_status"
        validate_window_size
      end
      
      private def validate_window_size : Nil
        if @rows.nil? != @columns.nil?
          raise ArgumentError.new("PTY rows and columns must be provided together")
        end
      
        if rows = @rows
          raise ArgumentError.new("PTY rows must be between 1 and 65535") if rows < 1 || rows > 65_535
        end
        if columns = @columns
          raise ArgumentError.new("PTY columns must be between 1 and 65535") if columns < 1 || columns > 65_535
        end
      end
    end

    getter raw_string : String
    getter rows : Int32?
    getter columns : Int32?
    getter status_path : String
    
    @argv : Array(String)?
    
    include Initialize
    
    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
      session = if argv = @argv
                  Session.new(argv, rows: @rows, columns: @columns, status_path: @status_path)
                else
                  Session.new(@raw_string, rows: @rows, columns: @columns, status_path: @status_path)
                end
      session.start(&stream_callback)
      exit_code = session.wait
      {session.output, exit_code}
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
        self
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
          ENV["TERM"] ||= "xterm-256color"
        
          begin
            if argv = @argv
              script = "( \"$@\" ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
              Process.exec("/bin/sh", ["-c", script, "pty-session"] + argv)
            else
              command = @raw_string.empty? ? ":" : @raw_string
              script = "( #{command} ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
              Process.exec("/bin/sh", ["-c", script])
            end
          rescue
            C._exit(127)
          end
          C._exit(127)
        end
      end

      module WaitForChild
        private def read_status_file(status_path : String) : Int32?
          return unless File.exists?(status_path)
        
          contents = File.read(status_path).strip
          return if contents.empty?
        
          File.delete(status_path)
          contents.to_i?
        end
        
        private def terminate_child_group(pid : Int32) : Nil
          if C.kill(-pid, 1) == 0
            sleep(50.milliseconds)
            C.kill(-pid, 9)
          elsif C.kill(pid, 1) == 0
            sleep(50.milliseconds)
            C.kill(pid, 9)
          end
        end
      end

      include AllocatePTY
      include SpawnChild
      include ReadOutput
      include WaitForChild
    end

    module Initialize
      def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil, status_path : String? = nil)
        @argv = nil
        @rows = rows
        @columns = columns
        @status_path = status_path || "/tmp/#{UUID.random}.pty_status"
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
      
      def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil, status_path : String? = nil)
        raise ArgumentError.new("PTY command must not be empty") if argv.empty?
        raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?
      
        @argv = argv.dup
        @raw_string = argv.join(" ")
        @rows = rows
        @columns = columns
        @status_path = status_path || "/tmp/#{UUID.random}.pty_status"
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
        loop do
          if code = read_status_file(@status_path)
            return code
          end
      
          if @reader_finished
            return 143 if @terminated || @stream_error
          else
            select
            when error = @reader_done.not_nil!.receive
              @reader_finished = true
              @stream_error ||= error
              if @stream_error
                terminate_child_group(@pid.not_nil!)
                return read_status_file(@status_path) || 143
              end
            when timeout(10.milliseconds)
            end
          end
          sleep(10.milliseconds) if @reader_finished && !@terminated && !@stream_error
        end
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
      end
    end

    getter raw_string : String
    getter rows : Int32?
    getter columns : Int32?
    getter status_path : String
    getter pid : Int32?
    getter exit_code : Int32?
    
    @argv : Array(String)?
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
