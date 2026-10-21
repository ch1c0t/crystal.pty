private def allocate_pty : Tuple(Int32, Int32)
  if PTY::C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
    raise "Error: OS failed to allocate high-precision PTY descriptors."
  end
  {master_fd, slave_fd}
end
