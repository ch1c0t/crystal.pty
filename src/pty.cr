module PTY
  lib C
    fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
    fun login_tty(fd : Int32) : Int32
    fun fork : Int32
    fun _exit(status : Int32) : NoReturn
    fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
    
    struct WinSize
      ws_row : UInt16
      ws_col : UInt16
      ws_xpixel : UInt16
      ws_ypixel : UInt16
    end
    
    fun kill(pid : Int32, signal : Int32) : Int32
    fun close(fd : Int32) : Int32
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
    
      module MonitorParentStream
        # Close the parent's copy of the slave and drain the master concurrently with
        # waitpid, preventing verbose commands from blocking on a full terminal buffer.
        private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, pid : Int32, &stream_callback : String -> Nil) : Tuple(String, Int32)
          C.close(slave_fd)
          master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
          accumulated_buffer = IO::Memory.new
          stream_done = Channel(Exception?).new(1)
        
          spawn do
            stream_error : Exception? = nil
            begin
              io_buffer = Bytes.new(4096)
              while (bytes_read = master_io.read(io_buffer)) > 0
                chunk = String.new(io_buffer[0, bytes_read])
                accumulated_buffer.write(io_buffer[0, bytes_read])
                begin
                  stream_callback.call(chunk)
                rescue ex
                  stream_error = ex
                  C.kill(-pid, 15)
                  break
                end
              end
            rescue ex : IO::Error
              # Linux PTYs report EIO when the final slave descriptor closes.
            rescue ex
              stream_error = ex
              C.kill(-pid, 15)
            ensure
              stream_done.send(stream_error)
            end
          end
        
          exit_code : Int32? = nil
          wait_error : Exception? = nil
          begin
            exit_code = wait_for_child(pid)
          rescue ex
            wait_error = ex
          ensure
            terminate_child_group(pid)
          end
        
          stream_error = stream_done.receive
          raise wait_error if wait_error
          raise stream_error if stream_error
          {accumulated_buffer.to_s, exit_code || 1}
        ensure
          master_io.try &.close
        end
      end
    
      module SpawnChild
        # login_tty creates a new session, makes the slave the controlling terminal,
        # and connects it to stdin, stdout and stderr before replacing this process.
        private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
          C.close(master_fd)
          C._exit(127) if C.login_tty(slave_fd) == -1
        
          ENV["TERM"] ||= "xterm-256color"
        
          begin
            if argv = @argv
              Process.exec(argv[0], argv)
            else
              Process.exec("/bin/sh", ["-c", @raw_string])
            end
          rescue
            C._exit(127)
          end
        
          C._exit(127)
        end
      end
    
      module WaitForChild
        private def wait_for_child(pid : Int32) : Int32
          loop do
            status = 0
            waited_pid = C.waitpid(pid, pointerof(status), 1) # WNOHANG
        
            if waited_pid == pid
              signal = status & 0x7f
              next if signal == 0x7f
              return (status >> 8) & 0xff if signal == 0
              return 128 + signal
            elsif waited_pid == 0
              sleep(10.milliseconds)
            else
              raise "waitpid failed for PTY child #{pid}"
            end
          end
        end
        
        # A command can exit while background descendants retain the slave terminal.
        # Signal the dedicated process group, then force it down after a short grace.
        private def terminate_child_group(pid : Int32) : Nil
          if C.kill(-pid, 1) == 0 # SIGHUP
            sleep(50.milliseconds)
            C.kill(-pid, 9) # SIGKILL
          end
        end
      end
    
      include AllocatePTY
      include SpawnChild
      include MonitorParentStream
      include WaitForChild
    end
  
    getter raw_string : String
    getter rows : Int32?
    getter columns : Int32?
    
    @argv : Array(String)?
    
    # Compatibility constructor used by tmux.run. The index and run_id remain part
    # of the API; they are intentionally not needed for child-status collection.
    def initialize(@raw_string : String, _index : Int32, _run_id : Int64, *, rows : Int32? = nil, columns : Int32? = nil)
      @argv = nil
      @rows = rows
      @columns = columns
      validate_window_size
    end
    
    def initialize(@raw_string : String, *, rows : Int32? = nil, columns : Int32? = nil)
      @argv = nil
      @rows = rows
      @columns = columns
      validate_window_size
    end
    
    # Prefer argv when shell parsing is not required.
    def initialize(argv : Array(String), *, rows : Int32? = nil, columns : Int32? = nil)
      raise ArgumentError.new("PTY command must not be empty") if argv.empty?
      raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?
    
      @argv = argv.dup
      @raw_string = argv.join(" ")
      @rows = rows
      @columns = columns
      validate_window_size
    end
    
    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
      master_fd, slave_fd = allocate_pty(@rows, @columns)
      pid = C.fork
    
      if pid < 0
        C.close(master_fd)
        C.close(slave_fd)
        raise "fork failed while starting PTY command"
      elsif pid == 0
        spawn_child(master_fd, slave_fd)
      else
        monitor_parent_stream(master_fd, slave_fd, pid, &stream_callback)
      end
    end
    
    def execute_inside_pty : Tuple(String, Int32)
      execute_inside_pty { |_chunk| }
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
    
    include Helpers
  end
end