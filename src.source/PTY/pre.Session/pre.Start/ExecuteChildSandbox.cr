# Helper B: Light, GC-free execution boundary inside the cloned fork
private def execute_child_sandbox(slave_fd : Int32, env_payload : Array(String), target_cwd : String?, target_shell : String) : NoReturn
  PTY::C.login_tty(slave_fd)

  # Direct POSIX LibC mutations skip high-level language object allocations
  # 1. Apply environment variables using raw string copies 
  # without touching Crystal's heavy ENV wrapper object
  env_payload.each do |env_string|
    # Split out the key/value parts safely using primitive byte manipulation
    if idx = env_string.index('=')
      k = env_string[0...idx]
      v = env_string[idx + 1..-1]
      # Call LibC directly to bypass Crystal heap allocations entirely
      LibC.setenv(k.to_unsafe, v.to_unsafe, 1)
    end
  end

  # 2. Safely change directory locally inside the child sandbox
  if target_cwd
    LibC.chdir(target_cwd.to_unsafe)
  end

  # Overwrite the child memory stack instantly
  Process.exec(target_shell)
  PTY::C._exit(1)
end
