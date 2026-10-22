# STRICTLY starts a vanilla interactive shell session without inputs or blocks
def start : self
  return self if started?

  master_fd, slave_fd = allocate_pty
  update_kernel_terminal_dimensions_by_fd(master_fd)

  # =========================================================================
  # PREPARE BARE PRIMITIVES BEFORE THE FORK (Safe parent heap space)
  # =========================================================================
  # Flatten env variables into primitive strings ahead of time
  env_payload = prepare_environment_variables.map { |k, v| "#{k}=#{v}" }
  target_shell = @shell
  target_cwd = @cwd

  pid = PTY::C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # INSIDE CHILD
    PTY::C.login_tty(slave_fd)

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

    # Launch the interactive base shell directly
    Process.exec(@shell)
    PTY::C._exit(1)
  else
    # INSIDE PARENT
    @process = Process.new(Crystal::System::Process.new(pid))
    monitor_parent_stream(master_fd, slave_fd)
  end
  self
end

include AllocatePTY
include UpdateKernelTerminalDimensions
include PrepareEnvironmentVariables
include MonitorParentStream
