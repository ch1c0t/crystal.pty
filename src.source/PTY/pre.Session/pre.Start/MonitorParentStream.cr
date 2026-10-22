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
