# STRICTLY starts a vanilla interactive shell session without inputs or blocks
def start : self
  # Guard against multiple accidental start calls
  if @started.get
    return self
  end

  master_fd, slave_fd = allocate_pty
  update_kernel_terminal_dimensions_by_fd(master_fd)

  pid = PTY::C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # INSIDE CHILD
    PTY::C.login_tty(slave_fd)
    prepare_environment_variables.each { |k, v| ENV[k] = v }

    if directory = @cwd
      Dir.cd(directory)
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
