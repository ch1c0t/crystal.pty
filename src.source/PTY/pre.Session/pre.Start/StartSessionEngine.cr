private def start_session_engine(args : Array(String)?, stream_callback : (String ->)?)
  master_fd, slave_fd = allocate_pty

  # Apply initial hardware window bounds directly inside descriptor registers
  update_kernel_terminal_dimensions_by_fd(master_fd)

  pid = PTY::C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # INSIDE THE CHILD PROCESS SANDBOX
    spawn_child(slave_fd, args)
  else
    # INSIDE THE PARENT PROCESS PROXY
    @process = Process.new(Crystal::System::Process.new(pid))
    monitor_parent_stream(master_fd, slave_fd, stream_callback)
  end
end

private def allocate_pty : Tuple(Int32, Int32)
  if PTY::C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
    raise "Error: OS failed to allocate high-precision PTY descriptors."
  end
  {master_fd, slave_fd}
end
