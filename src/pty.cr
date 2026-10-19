module PTY
  @[Link("util")]
  lib C
    struct WinSize
      ws_row : UInt16
      ws_col : UInt16
      ws_xpixel : UInt16
      ws_ypixel : UInt16
    end

    fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : WinSize*) : Int32
    fun kill(pid : Int32, signal : Int32) : Int32
    fun close(fd : Int32) : Int32
  end

  class Command
    module Helpers
      module AllocatePTY
        private def allocate_pty(rows : Int32, columns : Int32) : Tuple(Int32, Int32)
          window_size = C::WinSize.new
          window_size.ws_row = rows.to_u16
          window_size.ws_col = columns.to_u16
          window_size.ws_xpixel = 0_u16
          window_size.ws_ypixel = 0_u16

          if C.openpty(out master_fd, out slave_fd, nil, nil, pointerof(window_size)) == -1
            raise "Error: OS failed to allocate PTY descriptors."
          end
          {master_fd, slave_fd}
        end
      end

      module SpawnChild
        private def launch_process(slave_io : IO::FileDescriptor) : Process
          command = if argv = @argv
                      argv
                    else
                      ["/bin/sh", "-c", @raw_string]
                    end
          environment = {"TERM" => (ENV["TERM"]? || "xterm-256color")} of String => String?
          Process.new(["setsid", "-c", "--"] + command, env: environment, input: slave_io, output: slave_io, error: slave_io)
        end
      end

      module MonitorParentStream
        private def monitor_parent_stream(master_io : IO::FileDescriptor, process : Process, &stream_callback : String -> Nil) : Tuple(String, Int32)
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
                  C.kill(-process.pid.to_i32, 15)
                  break
                end
              end
            rescue ex : IO::Error
              # Linux PTYs commonly report EIO when the final slave closes.
            rescue ex
              stream_error = ex
              C.kill(-process.pid.to_i32, 15)
            ensure
              stream_done.send(stream_error)
            end
          end

          status : Process::Status? = nil
          wait_error : Exception? = nil
          begin
            status = process.wait
          rescue ex
            wait_error = ex
          ensure
            terminate_child_group(process.pid.to_i32)
          end

          stream_error = stream_done.receive
          raise wait_error if wait_error
          raise stream_error if stream_error
          child_status = status || raise("PTY child process completed without a status")

          exit_code = if child_status.normal_exit?
                        child_status.exit_code
                      elsif signal = child_status.exit_signal?
                        128 + signal.value
                      else
                        1
                      end
          {accumulated_buffer.to_s, exit_code}
        ensure
          master_io.try &.close
        end
      end

      module WaitForChild
        private def terminate_child_group(pid : Int32) : Nil
          if C.kill(-pid, 1) == 0
            sleep(50.milliseconds)
            C.kill(-pid, 9)
          end
        end
      end

      include AllocatePTY
      include SpawnChild
      include MonitorParentStream
      include WaitForChild
    end

    getter raw_string : String
    getter rows : Int32
    getter columns : Int32
    @argv : Array(String)?

    def initialize(@raw_string : String, _index : Int32, _run_id : Int64, *, rows : Int32 = 24, columns : Int32 = 80)
      @argv = nil
      @rows = rows
      @columns = columns
      validate_window_size
    end

    def initialize(@raw_string : String, *, rows : Int32 = 24, columns : Int32 = 80)
      @argv = nil
      @rows = rows
      @columns = columns
      validate_window_size
    end

    def initialize(argv : Array(String), *, rows : Int32 = 24, columns : Int32 = 80)
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
      master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
      slave_io = IO::FileDescriptor.new(slave_fd, close_on_finalize: true)

      process = begin
        launch_process(slave_io)
      rescue ex
        master_io.close
        raise ex
      ensure
        slave_io.close
      end

      monitor_parent_stream(master_io, process, &stream_callback)
    end

    def execute_inside_pty : Tuple(String, Int32)
      execute_inside_pty { |_chunk| }
    end

    private def validate_window_size : Nil
      if @rows < 1 || @rows > 65_535
        raise ArgumentError.new("PTY rows must be between 1 and 65535")
      end
      if @columns < 1 || @columns > 65_535
        raise ArgumentError.new("PTY columns must be between 1 and 65535")
      end
    end

    include Helpers
  end

  # One-shot runner for argv or shell commands.
  def self.run(command : String, *, rows : Int32 = 24, columns : Int32 = 80, &stream_callback : String -> Nil) : Tuple(String, Int32)
    Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
  end

  def self.run(command : Array(String), *, rows : Int32 = 24, columns : Int32 = 80, &stream_callback : String -> Nil) : Tuple(String, Int32)
    Command.new(command, rows: rows, columns: columns).execute_inside_pty(&stream_callback)
  end

  def self.run(command : String, *, rows : Int32 = 24, columns : Int32 = 80) : Tuple(String, Int32)
    Command.new(command, rows: rows, columns: columns).execute_inside_pty
  end

  def self.run(command : Array(String), *, rows : Int32 = 24, columns : Int32 = 80) : Tuple(String, Int32)
    Command.new(command, rows: rows, columns: columns).execute_inside_pty
  end
end
