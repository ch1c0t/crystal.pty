private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  C.close(master_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1

  begin
    ENV["TERM"] = @name
    if env = @env
      env.each { |key, value| ENV[key] = value }
    end
    Dir.cd(@cwd.not_nil!) if @cwd

    ready = "printf 'ready\\n' > '#{@ready_path}.tmp' && mv '#{@ready_path}.tmp' '#{@ready_path}'; "
    if argv = @argv
      command = "( \"$@\" ); command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", ready + command, "pty-session"] + argv)
    elsif command = @command
      script = "#{ready}\"$1\" -i -c \"$2\"; command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script, "pty-session", @shell, command])
    else
      shell = @shell.gsub("'", "'\\''")
      script = "#{ready}'#{shell}' -i; command_status=$?; printf '%s\\n' \"$command_status\" > '#{@status_path}.tmp' && mv '#{@status_path}.tmp' '#{@status_path}'; exit \"$command_status\""
      Process.exec("/bin/sh", ["-c", script])
    end
  rescue
    C._exit(127)
  end
  C._exit(127)
end
