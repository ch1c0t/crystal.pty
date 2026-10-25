# Child-side work must avoid Crystal allocation/runtime code after fork.
# All strings and pointer vectors are prepared in the parent before fork.
private def execute_child_sandbox(
  master_fd : Int32,
  slave_fd : Int32,
  executable_path : Pointer(UInt8),
  target_cwd : Pointer(UInt8),
  argv : Pointer(Pointer(UInt8)),
  envp : Pointer(Pointer(UInt8))
) : NoReturn
  PTY::C.close(master_fd)

  # login_tty performs the native controlling-terminal/stdin/stdout/stderr setup.
  PTY::C._exit(127) unless PTY::C.login_tty(slave_fd) == 0

  # chdir is async-signal-safe; the pointer was staged before the fork.
  if target_cwd != Pointer(UInt8).null
    LibC.chdir(target_cwd)
  end

  # Do not call Process.exec here: it allocates/builds envp in Crystal after fork.
  PTY::C.execve(executable_path, argv, envp)

  # execve returns only on failure. Never unwind through Crystal in this child.
  PTY::C._exit(127)
end
