def write(data : String) : Nil
  raise "PTY session has not been started" unless @started
  raise "PTY session has completed" if @completed

  @master_io.not_nil!.write(data.to_slice)
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

  child_pid = @pid
  child_pid != nil && C.kill(child_pid, 0) == 0
end
