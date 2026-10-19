# Close the inherited master, attach the slave as the controlling terminal,
# and replace the forked process with the requested command.
private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  PTYLibC.close(master_fd)
  PTYLibC._exit(127) if PTYLibC.login_tty(slave_fd) == -1
  ENV["TERM"] ||= "xterm-256color"

  begin
    if argv = @argv
      Process.exec(argv[0], argv)
    else
      Process.exec("/bin/sh", ["-c", @raw_string])
    end
  rescue
    PTYLibC._exit(127)
  end

  PTYLibC._exit(127)
end
