private def spawn_child(master_fd : Int32, slave_fd : Int32) : NoReturn
  C.close(master_fd)
  C._exit(127) if C.login_tty(slave_fd) == -1

  begin
    ENV["TERM"] = @name
    if env = @env
      env.each { |key, value| ENV[key] = value }
    end
    Dir.cd(@cwd.not_nil!) if @cwd
    File.write(@ready_path, "ready\\n")

    if argv = @argv
      Process.exec(argv.first, argv[1..])
    elsif command = @command
      Process.exec(@shell, ["-c", command])
    else
      Process.exec(@shell, ["-i"])
    end
  rescue
    C._exit(127)
  end
  C._exit(127)
end
