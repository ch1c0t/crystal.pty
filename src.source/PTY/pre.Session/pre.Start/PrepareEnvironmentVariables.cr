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
