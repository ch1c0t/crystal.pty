# Helper A: Packs our bags completely before crossing the border
private def stage_pre_flight_primitives : Tuple(Array(String), String, String?)
  env_payload = prepare_environment_variables.map { |k, v| "#{k}=#{v}" }
  {env_payload, @shell, @cwd}
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
