private def allocate_pty(rows : Int32?, columns : Int32?) : Tuple(Int32, Int32)
  if rows && columns
    window_size = C::WinSize.new
    window_size.ws_row = rows.to_u16
    window_size.ws_col = columns.to_u16
    window_size.ws_xpixel = 0_u16
    window_size.ws_ypixel = 0_u16

    if C.openpty(out master_fd, out slave_fd, nil, nil, pointerof(window_size).as(Void*)) == -1
      raise "Error: OS failed to allocate PTY descriptors."
    end
  else
    if C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
      raise "Error: OS failed to allocate PTY descriptors."
    end
  end

  {master_fd, slave_fd}
end
