private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  C.close(master_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1
  ENV["TERM"] ||= "xterm-256color"

  begin
    ready = "printf 'ready\\n' > '#{@ready_path}.tmp' && mv '#{@ready_path}.tmp' '#{@ready_path}'; "
    if argv = @argv
      command = "( \"$@\" ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", ready + command, "pty-session"] + argv)
    elsif @interactive_shell
      shell = (ENV["SHELL"]? || "/bin/sh").gsub("'", "'\\''")
      script = "#{ready}'#{shell}' -i; command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script])
    else
      command = @raw_string.empty? ? ":" : @raw_string
      script = "#{ready}( #{command} ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script])
    end
  rescue
    C._exit(127)
  end
  C._exit(127)
end
