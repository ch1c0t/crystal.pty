module PTY
  @[Link("util")]
  lib C
    fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
    fun login_tty(fd : Int32) : Int32
    fun fork : Int32
    fun _exit(status : Int32) : NoReturn
    fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
    fun kill(pid : Int32, signal : Int32) : Int32
    fun close(fd : Int32) : Int32
  end

  class Command
    module Helpers
      module AllocatePTY
        private def allocate_pty : Tuple(Int32, Int32)
          if C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
            raise "Error: OS failed to allocate PTY descriptors."
          end
          {master_fd, slave_fd}
        end
      end

      module SpawnChild
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

      module MonitorParentStream
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
              # Linux PTYs commonly report EIO when the final slave descriptor closes.
            rescue ex
              stream_error = ex
              C.kill(-pid, 15)
            ensure
              stream_done.send(stream_error)
            end
          end

          begin
            exit_code = wait_for_child(pid)
          rescue ex
            terminate_child_group(pid)
            stream_done.receive
            raise ex
          end

          terminate_child_group(pid)
          stream_error = stream_done.receive
          raise stream_error if stream_error

          {accumulated_buffer.to_s, exit_code}
        ensure
          master_io.close
        end
      end

      module WaitForChild
        private def wait_for_child(pid : Int32) : Int32
          loop do
            status = 0
            waited_pid = C.waitpid(pid, pointerof(status), 1)

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
    @argv : Array(String)?

    def initialize(@raw_string : String, _index : Int32, _run_id : Int64)
      @argv = nil
    end

    def initialize(@raw_string : String)
      @argv = nil
    end

    def initialize(argv : Array(String))
      raise ArgumentError.new("PTY command must not be empty") if argv.empty?
      raise ArgumentError.new("PTY executable must not be empty") if argv.first.empty?

      @argv = argv.dup
      @raw_string = argv.join(" ")
    end

    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
      master_fd, slave_fd = allocate_pty

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

    include Helpers
  end

  def self.run(command : String, &stream_callback : String -> Nil) : Tuple(String, Int32)
    Command.new(command).execute_inside_pty(&stream_callback)
  end

  def self.run(command : Array(String), &stream_callback : String -> Nil) : Tuple(String, Int32)
    Command.new(command).execute_inside_pty(&stream_callback)
  end

  def self.run(command : String) : Tuple(String, Int32)
    Command.new(command).execute_inside_pty
  end

  def self.run(command : Array(String)) : Tuple(String, Int32)
    Command.new(command).execute_inside_pty
  end
end
