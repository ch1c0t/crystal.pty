private def spawn_child(slave_fd : Int32, args : Array(String)?) : NoReturn
  PTY::C.login_tty(slave_fd)

  # Propagate configurations into system environment space
  prepare_environment_variables.each do |key, value|
    ENV[key] = value
  end

  if directory = @cwd
    Dir.cd(directory) rescue nil
  end

  command_vector = args && !args.empty? ? args : [@shell]
  command = command_vector[0]

  Process.exec(
    command: command,
    args: command_vector.size > 1 ? command_vector[1..-1] : nil
  )

  PTY::C._exit(1)
end
