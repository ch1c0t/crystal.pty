# login_tty creates a new session, makes the slave the controlling terminal,
# and connects it to stdin, stdout and stderr before replacing this process.
private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  C.close(master_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1

  ENV["TERM"] ||= "xterm-256color"

  begin
    if argv = @argv
      Process.exec(argv[0], argv)
    else
      Process.exec("/bin/sh", ["-c", @raw_string])
    end
  rescue
    C._exit(127)
  end

  C._exit(127)
end
