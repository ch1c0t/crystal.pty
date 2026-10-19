# login_tty creates a new session, makes the slave the controlling terminal,
# and connects it to stdin, stdout and stderr before replacing this process.
private def spawn_child(master_fd : Int32, slave_fd : Int32, status_read_fd : Int32, status_write_fd : Int32) : NoReturn
  C.close(master_fd)
  C.close(status_read_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1

  # POSIX /bin/sh supports single-digit redirection descriptors. Put the
  # private status writer on fd 3 after login_tty has established stdio.
  status_fd = status_write_fd
  if status_fd != 3
    C._exit(127) if C.dup2(status_fd, 3) == -1
    C.close(status_fd)
    status_fd = 3
  end

  ENV["TERM"] ||= "xterm-256color"

  begin
    if argv = @argv
      script = "( exec #{status_fd}>&-; \"$@\" ); command_status=$?; printf '%s\\n' \"$command_status\" >&#{status_fd}; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script, "pty-command"] + argv)
    else
      command = @raw_string.empty? ? ":" : @raw_string
      script = "( exec #{status_fd}>&-; #{command} ); command_status=$?; printf '%s\\n' \"$command_status\" >&#{status_fd}; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script])
    end
  rescue
    C._exit(127)
  end

  C._exit(127)
end
