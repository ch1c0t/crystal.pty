# Helper A: Packs arguments and environment completely before crossing the fork boundary
private def stage_pre_flight_primitives : Tuple(Array(String), String, String, String?)
  process_env = prepare_environment_variables
  env_payload = process_env.map { |k, v| "#{k}=#{v}" }

  target_shell = @shell
  search_path = process_env["PATH"]? || "/usr/bin:/bin"
  target_executable = Process.find_executable(target_shell, search_path, @cwd || Dir.current) ||
    raise "PTY shell executable not found: #{target_shell}"

  {env_payload, target_shell, target_executable, @cwd}
end

private def prepare_environment_variables : Hash(String, String)
  process_env = ENV.to_h

  if terminal_name = @name
    process_env["TERM"] = terminal_name
  end

  if custom_env = @env
    process_env.merge!(custom_env)
  end

  process_env
end
