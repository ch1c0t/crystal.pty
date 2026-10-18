# Helper 2: Sets up the slave terminal environment and hands control to the shell
private def spawn_child(slave_fd : Int32) : NoReturn
  C.login_tty(slave_fd)
  ENV["TERM"] = "xterm-256color"
  
  # Overwrite child memory stack with a fresh subshell execution block
  Process.exec("/bin/sh", ["-c", "( #{@raw_string} ); echo $? > #{@status_path}"])
  C._exit(1)
end
