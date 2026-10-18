require "uuid"

module PTY

  class Command
    module Helpers
      module AllocatePTY
        # Helper 1: Allocates the master and slave kernel file descriptors
        private def allocate_pty : Tuple(Int32, Int32)
          if C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
            raise "Error: OS failed to allocate high-precision PTY descriptors."
          end
          {master_fd, slave_fd}
        end
      end
    
      module MonitorParentStream
        # Helper 3: Encapsulates async fiber creation, buffer logging, and blocking loops
        private def monitor_parent_stream(master_fd : Int32, slave_fd : Int32, &stream_callback : String -> Nil) : Tuple(String, Int32)
          IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close
          
          master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
          accumulated_buffer = IO::Memory.new
          stream_done = Channel(Nil).new
        
          # Fire background fiber for real-time unblocked read updates
          spawn do
            begin
              io_buffer = Bytes.new(4096)
              while (bytes_read = master_io.read(io_buffer)) > 0
                chunk = String.new(io_buffer[0, bytes_read])
                accumulated_buffer.write(io_buffer[0, bytes_read])
                stream_callback.call(chunk) # Stream directly to the block yield argument
              end
            rescue IO::Error
              # EIO safely caught when slave drops out
            ensure
              stream_done.send(nil)
            end
          end
        
          # Wait for process termination and ensure file tracking clears safely
          exit_code = wait_for_status_file
          stream_done.receive
        
          {accumulated_buffer.to_s, exit_code}
        end
      end
    
      module SpawnChild
        # Helper 2: Sets up the slave terminal environment and hands control to the shell
        private def spawn_child(slave_fd : Int32) : NoReturn
          C.login_tty(slave_fd)
          ENV["TERM"] = "xterm-256color"
          
          # Overwrite child memory stack with a fresh subshell execution block
          Process.exec("/bin/sh", ["-c", "( #{@raw_string} ); echo $? > #{@status_path}"])
          C._exit(1)
        end
      end
    
      module WaitForStatusFile
        # Helper 4: Blocks until the status sync file has completed writing
        private def wait_for_status_file : Int32
          while !File.exists?(@status_path)
            sleep(50.milliseconds)
          end
        
          exit_code = File.read(@status_path).strip.to_i
          File.delete(@status_path) if File.exists?(@status_path)
          exit_code
        end
      end
    
      include AllocatePTY
      include SpawnChild
      include MonitorParentStream
      include WaitForStatusFile
    end
  
    getter raw_string : String
    getter status_path : String
    
    def initialize(@raw_string, index : Int32, run_id : Int64)
      @status_path = "/tmp/#{UUID.random}.pty_status_#{run_id}_#{index}.txt"
    end
    
    def execute_inside_pty(&stream_callback : String -> Nil) : Tuple(String, Int32)
      master_fd, slave_fd = allocate_pty
    
      pid = C.fork
      if pid < 0
        raise "Error: OS process fork failed."
      elsif pid == 0
        # Inside the Child Process sandbox
        spawn_child(slave_fd)
      else
        # Inside the Parent Process proxy monitor
        monitor_parent_stream(master_fd, slave_fd, &stream_callback)
      end
    end
    
    include Helpers
  end
end