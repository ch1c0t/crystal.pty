# STRICTLY starts a vanilla interactive shell session without inputs or blocks
def start : self
  debug_log("start :: Boot Sequence Triggered", {
    target_shell: @shell,
    dimensions: "#{@rows} rows x #{@columns} columns",
    working_dir: @cwd,
    custom_env: @env
  })

  # Guard against booting an already running process.
  if @started.swap(true)
    debug_log("start :: Already Running", "")
    return self
  end

  # Pre-flight resolves PATH and builds every argument/environment string before
  # any fork. If the executable is invalid, no PTY descriptors have been allocated.
  begin
    env_payload, target_shell, target_executable, target_cwd = stage_pre_flight_primitives
  rescue ex
    @started.set(false)
    raise ex
  end

  argv = [target_shell.to_unsafe, Pointer(UInt8).null]
  envp = [] of Pointer(UInt8)
  env_payload.each { |entry| envp << entry.to_unsafe }
  envp << Pointer(UInt8).null

  # Keep all memory referenced by argv/envp rooted across any parent-side GC
  # that can run before fork; the child uses the inherited bytes directly.
  @child_launch_buffers = {env_payload, target_executable, argv, envp}

  # Evaluate all managed-string / Array accessors before fork. The child receives
  # only raw pointers to memory that already exists in its forked address space.
  executable_path_ptr = target_executable.to_unsafe
  target_cwd_ptr = target_cwd ? target_cwd.to_unsafe : Pointer(UInt8).null
  argv_ptr = argv.to_unsafe
  envp_ptr = envp.to_unsafe

  # Allocate descriptors only once pre-flight has succeeded.
  master_fd, slave_fd = allocate_pty
  update_kernel_terminal_dimensions_by_fd(master_fd)

  # Process Split Boundary
  pid = PTY::C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # INSIDE CHILD: pass only native pointers and file descriptors.
    execute_child_sandbox(master_fd, slave_fd, executable_path_ptr, target_cwd_ptr, argv_ptr, envp_ptr)
  else
    # INSIDE PARENT
    initialize_parent_proxy(pid, slave_fd, master_fd)
    debug_log("start :: Initial Shell Settlement Sync Guard", {
      waiting_for_token: "$ ",
      current_history_size: output.bytesize
    })
    wait_for("$ ") rescue nil
    @child_launch_buffers = nil
  end

  debug_log("start :: Boot Sequence Complete", {
    final_history_snapshot: output
  })

  self
end

include AllocatePTY
include UpdateKernelTerminalDimensions
include StagePreFlightPrimitives
include ExecuteChildSandbox
include InitializeParentProxy
