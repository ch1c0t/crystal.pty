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
