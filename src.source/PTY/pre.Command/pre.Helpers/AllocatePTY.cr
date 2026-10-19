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
