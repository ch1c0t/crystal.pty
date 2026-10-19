# login_tty creates a new session, makes the slave the controlling terminal,
# and connects it to stdin, stdout and stderr before replacing this process.
private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  C.close(master_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1

  ENV["TERM"] ||= "xterm-256color"

  begin
    if argv = @argv
      script = "( \"$@\" ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script, "pty-command"] + argv)
    else
      command = @raw_string.empty? ? ":" : @raw_string
      script = "( #{command} ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script])
    end
  rescue
    C._exit(127)
  end

  C._exit(127)
end
